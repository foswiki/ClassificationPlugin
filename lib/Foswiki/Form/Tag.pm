# Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# 
# Copyright (C) 2007-2014 Michael Daum http://michaeldaumconsulting.com
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
# 
# As per the GPL, removal of this notice is prohibited.

package Foswiki::Form::Tag;
use Foswiki::Func ();
use Foswiki::Form::Textboxlist ();
our @ISA = ('Foswiki::Form::Textboxlist');

use strict;

sub renderForDisplay {
    my ( $this, $format, $value, $attrs, $web, $topic ) = @_;
    # SMELL: working around the topicObj not being added to the renderForDisplay API as it does for
    # renderForEdit, by using some extra params ... *shudder*

    if ( !$attrs->{showhidden} ) {
        my $fa = $this->{attributes} || '';
        if ( $fa =~ /H/ ) {
            return '';
        }
    }

    my $baseWeb = $this->{session}->{webName};
    my $baseTopic = $this->{session}->{topicName};
    $web ||= $baseWeb;

    my $context = Foswiki::Func::getContext();

    my @value = ();
    foreach my $tag (split(/\s*,\s*/, $value)) {
      my $url = '';
      if ($context->{SolrPluginEnabled}) {
        $url = Foswiki::Func::getScriptUrl($web, "WebSearch", "view", 
          filter=>"tag:$tag",
          origtopic=>"$baseWeb.$baseTopic"
        );
      } else {
        $url = Foswiki::Func::getScriptUrl($web, "WebTagCloud", "view", tag=>$tag);
      }

      push @value, "<a href='$url'>$tag</a>";
    }
    $value = join(', ', @value);

    return $this->SUPER::renderForDisplay($format, $value, $attrs);
}

sub renderForEdit {
  my ($this, $param1, $param2, $param3) = @_;

  my $value;
  my $web;
  my $topic;
  my $topicObject;
  if (ref($param1)) { # Foswiki >= 1.1
    $topicObject = $param1;
    $web = $topicObject->web;
    $topic = $topicObject->topic;
    $value = $param2;
  } else {
    $web = $param1;
    $topic = $param2;
    $value = $param3;
  }
  $value = '' unless defined $value;

  Foswiki::Func::readTemplate("classificationplugin");
  my $baseWeb = $this->{session}->{webName};

  my $widget = Foswiki::Func::expandTemplate("tageditor");
  $widget =~ s/\$baseweb/$baseWeb/g;
  $widget =~ s/\$web/$web/g;
  $widget =~ s/\$topic/$topic/g;
  $widget =~ s/\$value/$value/g;
  $widget =~ s/\$name/$this->{name}/g;
  $widget =~ s/\$title/$this->{title}/g;
  $widget =~ s/\$type/$this->{type}/g;
  $widget =~ s/\$size/$this->{size}/g;
  $widget =~ s/\$attrs/$this->{attributes}/g;
  $widget =~ s/\$(name|type|size|value|attrs)//g;

  return ('', Foswiki::Func::expandCommonVariables($widget, $topic, $web));

}

1;
