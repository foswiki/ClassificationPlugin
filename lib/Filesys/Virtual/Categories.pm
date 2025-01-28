# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Filesys::Virtual::Categories;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::ClassificationPlugin ();
use Filesys::Virtual::Attachments ();
our @ISA = ('Filesys::Virtual::Foswiki');

#use Data::Dump qw(dump);
use constant NOCAT => '00.uncategorized';

sub new {
  my $class = shift;
  my $args = shift;

  my $this = bless($class->SUPER::new($args), $class);

  $this->{attachmentsDirExtension} = '';
  $this->{hideEmptyCategories} = $Foswiki::cfg{Plugins}{FilesysVirtualPlugin}{HideEmptyCategories}
    || 0;

  return $this;
}

# Break a resource into its component parts, web, category, topic, attachment.
# The return value is an array which may have up to 3 entries:
# [0] is always the full web path name
# [1] is always the topic name with no suffix
# [2] is the attachment name
# [3] is the category
# if the array is empty, that indicates the root (/)
sub _parseResource {
  my ($this, $resource) = @_;

  my @path = $this->_getPathOfResource($resource);
  my $path = join("/", @path);

  my $info = $this->{_infoOfResource}{$path};
  return $info if defined $info;

  $info = {
    type => 'R',
    resource => $resource,
    path => $path,
  };

  $this->_parseWebOfResource($info, \@path);
  $this->_parseCategoryOfResource($info, \@path);
  $this->_parseTopicOfResource($info, \@path);
  $this->_parseAttachmentOfResource($info, \@path);
  $this->_parseViewOfResource($info, \@path);
  $this->_parseFileOfResource($info, \@path);

  # anything else is an error
  return if scalar(@path);

  # init topic for compatibility with upper level
  $info->{topic} ||= $info->{category};

  #print STDERR "... info=".dump($info)."\n";
  $this->{_infoOfResource}{$path} = $info;

  return $info;
}

sub _parseViewOfResource {
  my ($this, $info, $path) = @_;

  return unless $info->{web} && $info->{topic} && $info->{attachment} && $path;

  my $viewFile = "01.$info->{topic}";

  foreach my $v (@{$this->{views}}) {
    my $ext = $v->extension;
    if ($info->{attachment} =~ /^$viewFile$ext$/) {
      $info->{type} = 'T';
      $info->{view} = $v;
      last;
    }
  }
}

sub _parseCategoryOfResource {
  my ($this, $info, $path) = @_;

  return unless $info->{web} && $path;

  print STDERR "called _parseCategoryOfResource(@$path)\n" if $this->{trace} & 4;

  my $cat = '';
  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});

  my $part = $path->[0];

  while ($part && ($part eq NOCAT || $hierarchy->getCategory($part))) {
    $cat = $part;
    shift @$path;
    $part = $path->[0];
  }

  if ($cat) {
    $info->{category} = $cat;
    $info->{topic} = $cat;
    $info->{type} = 'C';

    print STDERR "... cat=$cat\n" if $this->{trace} & 2;
  }

  return $cat;
}

sub _D_list {
  my ($this, $info) = @_;

  my $list = $this->SUPER::_D_list($info);

  foreach my $v (@{$this->{views}}) {
    push @$list, "01.$info->{topic}".$v->extension;
  }

  return $list;
}

sub _C_displayName {
  my ($this, $info) = @_;

  if ( Foswiki::Func::webExists( $info->{web} ) ) {
      my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});
      my $cat = $hierarchy->getCategory($info->{category});
      return $cat->title if $cat;
  }
}

sub _C_chdir {
  my ($this, $info) = @_;

  if (Foswiki::Func::topicExists($info->{web}, $info->{topic})) {
    $this->{path} = $info->{path};
    return $this->{path};
  }
  return;
}

sub _W_list {
  my ($this, $info) = @_;

  return $this->_fail(POSIX::ENOENT, $info)
    unless Foswiki::Func::webExists($info->{web});
  return $this->_fail(POSIX::EACCES, $info)
    unless $this->_haveAccess('VIEW', $info->{web});

  my @list = ();

  foreach my $sweb (Foswiki::Func::getListOfWebs('user,public')) {
    next if $sweb eq $info->{web};
    next unless $sweb =~ s/^$info->{web}\b.//;
    next if $sweb =~ m#/#;
    push(@list, $sweb);
  }

  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});

  # add top category
  my $cat = $hierarchy->getCategory("TopCategory");

  if ($this->{hideEmptyCategories}) {
    foreach my $child ($cat->getChildren()) {
      my $catName = $child->{name};
      next if $catName eq 'BottomCategory';
      $catName = '.' . $catName unless $child->countTopics();
      push @list, $catName;
    }
  } else {
    push @list, grep { !/^BottomCategory$/ } map { $_->{name} } $cat->getChildren();
  }

  # add no category
  push @list, NOCAT;

  push @list, '.';
  push @list, '..';
  push(@list, $this->{resourceLinkFileName}) if $this->{resourceLinkFileName};

#  foreach my $v (@{$this->{views}}) {
#    push @list, "01.$info->{web}".$v->extension;
#  }

  return \@list;
}

sub _C_list {
  my ($this, $info) = @_;

  return $this->_fail(POSIX::ENOENT, $info)
    unless Foswiki::Func::webExists($info->{web});
  return $this->_fail(POSIX::EACCES, $info)
    unless $this->_haveAccess('VIEW', $info->{web});

  my @list = ();

  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});
  my $cat;

  if ($info->{category} eq NOCAT) {
    $cat = $hierarchy->getCategory('TopCategory');
  } else {
    $cat = $hierarchy->getCategory($info->{category});
    return $this->_fail(POSIX::ENOENT, $info) unless $cat;

    # add child categories

    if ($this->{hideEmptyCategories}) {
      foreach my $child ($cat->getChildren()) {
        my $catName = $child->{name};
        next if $catName eq 'BottomCategory';
        $catName = '.' . $catName unless $child->countTopics();
        push @list, $catName;
      }
    } else {
      push @list, grep { !/^BottomCategory$/ }
        map { $_->{name} } $cat->getChildren();
    }

    # add attachments to this category topic
    push @list, grep { !/$this->{excludeAttachments}/ } Foswiki::Func::getAttachmentList($info->{web}, $info->{category});
  }

  # add topics in that category
  if ($this->{hideEmptyAttachmentDirs}) {
    foreach my $topic ($cat->getTopics) {
      $topic = '.' . $topic
        unless $this->_hasAttachments($info->{web}, $topic);
      push @list, $topic;
    }
  } else {
    push @list, $cat->getTopics();
  }

  push @list, '.';
  push @list, '..';
  push(@list, $this->{resourceLinkFileName}) if $this->{resourceLinkFileName} && $info->{category} ne NOCAT;

  foreach my $v (@{$this->{views}}) {
    push @list, "01.$info->{category}".$v->extension;
  }

  return \@list;
}

# deny - better don't delete categories using webdav for now
sub _C_delete {
  return shift->_fail(POSIX::EPERM, @_);
}

# deny - can't mkdir categories
sub _C_mkdir {
  return shift->_fail(POSIX::EPERM, @_);
}

sub _C_open_read {
  return shift->_fail(POSIX::EPERM, @_);
}

sub _C_open_write {
  return shift->_fail(POSIX::EPERM, @_);
}

# TODO
sub _C_rename {
  return shift->_fail(POSIX::EPERM, @_);
}

# TODO
sub _C_rmdir {
  return shift->_fail(POSIX::EPERM, @_);
}

sub _C_stat {
  my ($this, $info) = @_;

  #print STDERR "called _C_stat($info->{category})\n";

  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});
  my $catName = $info->{category} eq NOCAT ? 'TopCategory' : $info->{category};
  my $cat = $hierarchy->getCategory($catName);

  return () unless $cat;

  my $file = "$Foswiki::cfg{DataDir}/$cat->{origWeb}/$catName.txt";
  my @stat = CORE::stat($file);
  $stat[2] = $this->_getMode($cat->{origWeb}, $catName);
  $stat[2] = ($stat[2] & ~(222))
    if $cat->{origWeb} ne $info->{web} || $info->{category} eq NOCAT;

  #printf STDERR "mode=%#o\n", $stat[2];

  return @stat;
}

sub _C_test {
  my ($this, $info, $type) = @_;

  #print STDERR "called _C_test($info->{category}, $type)\n";

  return $this->_fail(POSIX::ENOENT, $info)
    unless Foswiki::Func::webExists($info->{web});
  return $this->_fail(POSIX::EACCES, $info)
    unless $this->_haveAccess('VIEW', $info->{web});

  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($info->{web});
  my $catName = $info->{category} eq NOCAT ? 'TopCategory' : $info->{category};
  my $cat = $hierarchy->getCategory($catName);

  return ($cat ? 1 : 0) if $type eq 'e' || $type eq 'd';
  return ($cat ? $this->_haveAccess('VIEW', $cat->{origWeb}, $catName) : 0)
    if $type =~ /r/i;
  return ($cat ? ($cat->{origWeb} eq $info->{web} ? 1 : 0) : 0)
    if $type =~ /w/i;

  return 1 if $type =~ /x/i;
  return 1 if $type =~ /o/i;

  return 0 if $type eq 'f';
  return 0 if $type eq 'T';
  return 0 if $type eq 'B';

  return ($cat ? scalar($cat->getChildren) == 0 : 0) if $type eq 'z';
  return ($cat ? scalar($cat->getChildren) : 0) if $type eq 's';

  # missing: l
  # off: p, S, b, t, u, g, k, M

  my $file = "$Foswiki::cfg{PubDir}/$cat->{origWeb}/$catName.txt";

  return eval "-$type $file";
}

# deny any modifications of a view
sub _T_delete {
    return shift->_fail( POSIX::EPERM, @_ );
}

sub _T_rename {
  return shift->_fail(POSIX::EPERM, @_);
}


1;
