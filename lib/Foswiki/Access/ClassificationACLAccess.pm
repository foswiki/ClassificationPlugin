# See bottom of file for license and copyright information

=pod

---+ package Foswiki::Access::ClassificationACLAccess

Implements the traditional, longstanding ACL in topic preference style.

=cut

package Foswiki::Access::ClassificationACLAccess;

use strict;
use warnings;
use Assert;

use Foswiki ();
use Foswiki::Address ();
use Foswiki::Meta ();
use Foswiki::Users ();
use Foswiki::Func ();
use Foswiki::Access::TopicACLAccess ();
our @ISA = qw(Foswiki::Access::TopicACLAccess);

use constant MONITOR => 0;

BEGIN {
  if ($Foswiki::cfg{UseLocale}) {
    require locale;
    import locale();
  }
}

=begin TML

---++ ObjectMethod haveAccess($mode, $User, $web, $topic, $attachment) -> $boolean
---++ ObjectMethod haveAccess($mode, $User, $meta) -> $boolean
---++ ObjectMethod haveAccess($mode, $User, $address) -> $boolean

   * =$mode=  - 'VIEW', 'CHANGE', 'CREATE', etc. (defaults to VIEW)
   * =$cUID=    - Canonical user id (defaults to current user)
Check if the user has the given mode of access to the topic. This call
may result in the topic being read.

=cut

sub haveAccess {
  my ($this, $mode, $cUID, $param1, $param2, $param3) = @_;

  my $session = $this->{session};
  $mode ||= 'VIEW';
  $cUID ||= $session->{user};

  undef $this->{failure};

  return 1 if Foswiki::Func::isAnAdmin($cUID);
  return 1 if defined $Foswiki::cfg{LoginManager} && $Foswiki::cfg{LoginManager} eq 'none';

  my $meta;

  if (ref($param1) eq '') {

    #scalar - treat as web, topic
    $meta = Foswiki::Meta->load($session, $param1, $param2);
    ASSERT(not defined($param3))
      if DEBUG;    #attachment ACL not currently supported in traditional topic ACL
  } else {
    if (ref($param1) eq 'Foswiki::Address') {
      $meta =
        Foswiki::Meta->load($session, $param1->web(), $param1->topic());
    } else {
      $meta = $param1;
    }
  }

  if (MONITOR) {
    print STDERR "*** checking ".$meta->getPath()." for $mode\n";
    print STDERR "param1=".($param1||'undef').", param2=".($param2||'undef').", param3=".($param3||'undef')."\n";
  }

  $mode = uc($mode);
  my $access = $this->SUPER::haveAccess($mode, $cUID, $meta);
  return 0 unless $access;

  my ($allow, $deny);

  if ($meta->{_topic}) {

    # check topic type
    my $topicType = $meta->get("FIELD", "TopicType");

    print STDERR "topicType=".($topicType?$topicType->{value}:'undef').", access=$access\n" if MONITOR;
    return $access if !$topicType || $topicType->{value} !~ /\bCategory\b/;

    # handle category topics
    $allow = $this->_getWebACL($meta, 'ALLOWCATEGORY' . $mode);
    $deny = $this->_getWebACL($meta, 'DENYCATEGORY' . $mode);

    if (MONITOR) {
      print STDERR "ALLOWCATEGORY" . $mode . ": " . (defined($allow) ? join(',', @$allow) : "undef") . "\n";
      print STDERR "DENYCATEGORY" . $mode . ": " . (defined($deny) ? join(',', @$deny) : "undef") . "\n";
    }

    # Check DENYCATEGORY
    if (defined($deny)) {
      if (scalar(@$deny) != 0) {
        if ($session->{users}->isInUserList($cUID, $deny)) {
          $this->{failure} = $session->i18n->maketext('access denied on category');
          print STDERR 'a ' . $this->{failure}, "\n" if MONITOR;
          return 0;
        }
      } elsif ($Foswiki::cfg{AccessControlACL}{EnableDeprecatedEmptyDeny}) {

        # If DENYCATEGORY is empty, don't deny _anyone_
        # DEPRECATED SYNTAX.   Recommended replace with "ALLOWCATEGORY=*"
        print STDERR "Access allowed: deprecated DENYCATEGORY is empty\n"
          if MONITOR;
        return 1;
      }
    }

    # Check ALLOWCATEGORY. If this is defined the user _must_ be in it
    if (defined($allow) && scalar(@$allow) != 0) {
      if ($session->{users}->isInUserList($cUID, $allow)) {
        print STDERR "in ALLOWCATEGORY\n" if MONITOR;
        return 1;
      }
      $this->{failure} = $session->i18n->maketext('access not allowed on category');
      print STDERR 'b ' . $this->{failure}, "\n" if MONITOR;
      return 0;
    }

    $meta = $meta->getContainer();    # Web
  }

  return 1;
}

# use Foswiki::Func::getPreferencesValue instead of just fetching ACLs from the current $meta obj
sub _getWebACL {
  my ($this, $meta, $mode) = @_;

  Foswiki::Func::pushTopicContext($meta->web, $meta->topic);
  my $text = Foswiki::Func::getPreferencesValue($mode);
  Foswiki::Func::popTopicContext();

  return undef unless defined $text;

  # Remove HTML tags (compatibility, inherited from Users.pm
  $text =~ s/(<[^>]*>)//g;

  # Dump the users web specifier if userweb
  my @list = grep { /\S/ } map {
    s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    $_
  } split(/[,\s]+/, $text);

  #print STDERR "getACL($mode): ".join(', ', @list)."\n";

  return \@list;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2015-2019 Michael Daum http://michaeldaumconsulting.com

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
