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

package Foswiki::Plugins::ClassificationPlugin;

=begin TML

---+ package Foswiki::Plugins::ClassificationPlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Contrib::DBCacheContrib::Search ();
use Foswiki::Request();
  
our $VERSION = '8.00';
our $RELEASE = '%$RELEASE%';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'A topic classification plugin and application';
our $LICENSECODE = '%$LICENSECODE%';

our $jsTreeConnector;
our $core;
our $services;
our $origSubscriptionMatches;

BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless ( Foswiki::Request->can('multi_param') ) {
      no warnings 'redefine'; ## no critic
      *Foswiki::Request::multi_param = \&Foswiki::Request::param;
      use warnings 'redefine';
  }

  # monkey-patch MailerContrib
  require Foswiki::Contrib::MailerContrib::Subscription;

  no warnings 'redefine';  ## no critic
  $origSubscriptionMatches = \&Foswiki::Contrib::MailerContrib::Subscription::matches;
  *Foswiki::Contrib::MailerContrib::Subscription::matches = \&Foswiki::Plugins::ClassificationPlugin::subscriptionMatches;
  use warnings 'redefine';
};

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  Foswiki::Func::registerTagHandler('HIERARCHY', sub {
    return getCore()->handleHIERARCHY(@_);
  });

  Foswiki::Func::registerTagHandler('ISA', sub {
    return getCore()->handleISA(@_);
  });

  Foswiki::Func::registerTagHandler('SUBSUMES', sub {
    return getCore()->handleSUBSUMES(@_);
  });

  Foswiki::Func::registerTagHandler('SIMILARTOPICS', sub {
    return getCore()->handleSIMILARTOPICS(@_);
  });

  Foswiki::Func::registerTagHandler('CATINFO', sub {
    return getCore()->handleCATINFO(@_);
  });

  Foswiki::Func::registerTagHandler('TAGINFO', sub {
    return getCore()->handleTAGINFO(@_);
  });

  Foswiki::Func::registerTagHandler('DISTANCE', sub {
    return getCore()->handleDISTANCE(@_);
  });

  Foswiki::Func::registerRESTHandler('jsTreeConnector', sub {
      return getJsTreeConnector()->dispatchAction(@_);
    }, 
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('splitfacet', sub {
    return getServices()->splitFacet(@_);
  }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('renametag', sub {
      return getServices()->renameTag(@_);
    }, 
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('normalizetags', sub {
    return getServices()->normalizeTags(@_);
  }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('deployTopicType', sub {
    return getServices()->deployTopicType(@_);
  }, 
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('updateCache', \&restUpdateCache, 
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name => 'SUBSUMES',
    prec => 4,
    arity => 2,
    exec => sub {
      return getCore()->OP_subsumes(@_);
    }
  );

  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name => 'ISA',
    prec => 4,
    arity => 2,
    exec => sub {
      return getCore()->OP_isa(@_);
    }
  );

  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name => 'DISTANCE',
    prec => 5,
    arity => 2,
    exec => sub {
      return getCore()->OP_distance(@_);
    }
  );

  Foswiki::Func::addToZone('head', 'CLASSIFICATIONPLUGIN::CSS', <<'HERE', 'JQUERYPLUGIN::FOSWIKI');
<link rel="stylesheet" type="text/css" href="%PUBURLPATH%/%SYSTEMWEB%/ClassificationPlugin/build/styles.css" media="all" />
HERE

  if (exists $Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
    Foswiki::Plugins::SolrPlugin::registerIndexAttachmentHandler(sub {
      return getCore()->solrIndexAttachmentHandler(@_);
    });
  }

  return 1;
}

=begin TML

---++ finishPlugin

finish the plugin and the core if it has been used,
automatically called during the core initialization process

=cut

sub finishPlugin {

  getCore()->finish(@_) if defined $core;
  getServices()->finish(@_) if defined $services;

  undef $services;
  undef $core;
  undef $jsTreeConnector;
}

=begin TML

---++ getCore() -> $core

returns a singleton Foswiki::Plugins::ClassificationPlugin::Core object for this plugin; a new core is allocated 
during each session request; once a core has been created it is destroyed during =finishPlugin()=

=cut

sub getCore {

  unless (defined $core) {
    require Foswiki::Plugins::ClassificationPlugin::Core;
    $core = Foswiki::Plugins::ClassificationPlugin::Core->new();
  }

  return $core;
}

=begin TML

---++ getServices() -> $services

returns a singleton Foswiki::Plugins::ClassificationPlugin::Services object for this plugin;

=cut

sub getServices {

  unless (defined $services) {
    require Foswiki::Plugins::ClassificationPlugin::Services;
    $services = Foswiki::Plugins::ClassificationPlugin::Services->new();
  }

  return $services;
}

=begin TML

---++ getJsTreeConnector() -> $jsTreeConnector

returns a singleton Foswiki::Plugins::ClassificationPlugin::JSTreeConnector object for this plugin

=cut

sub getJsTreeConnector {

  unless (defined $jsTreeConnector) {
    require Foswiki::Plugins::ClassificationPlugin::JSTreeConnector;
    $jsTreeConnector = Foswiki::Plugins::ClassificationPlugin::JSTreeConnector->new();
  }

  return $jsTreeConnector;
}

=begin TML

---++ beforeSaveHandler() 

called before a topic is saved

=cut

sub beforeSaveHandler {
  return getCore()->beforeSaveHandler(@_);
}

=begin TML

---++ afterSaveHandler() 

called after a topic is saved

=cut

sub afterSaveHandler {
  return getCore()->afterSaveHandler(@_);
}

=begin TML

---++ afterRenameHandler() 

called after a topic or attachment has been renamed

=cut

sub afterRenameHandler {
  return getCore()->afterRenameHandler(@_);
}

=begin TML

---++ getHierarchy($web) -> $hierarchy

gets a hierarchy object for a web

=cut

sub getHierarchy {
  return getCore()->getHierarchy(@_);
}

=begin TML

---++ getHierarchyFromTopic($web, $topic) -> $hierarchy

gets a hierarchy object for a web

=cut

sub getHierarchyFromTopic {
  return getCore()->getHierarchyFromTopic(@_);
}

=begin TML

---++ getHierarchyFromText($text) -> $hierarchy

returns a hierarchy object for a given bullet list

=cut

sub getHierarchyFromText {
  return getCore()->getHierarchyFromText(@_);
}

=begin TML

---++ subscriptionMatches($topics, $db, $depth) -> $boolean

This is our impl of Foswiki::Contrib::MailerContrib::Subscription::matches()
to implement subscription to a category: notify about changes of any topic
covered by a category the user is subscribed to

=cut

sub subscriptionMatches {
  my ($this, $topics, $db, $depth) = @_;

  return 0 unless $topics;
  $topics = [$topics] unless ref $topics;

  my $found = &$origSubscriptionMatches($this, $topics, $db, $depth);
  return $found if $found || !$db || !$db->{web};

  my $web = $db->{web};
  $web =~ s/\//./g;
  my $hierarchy = getHierarchy($web);
  return 0 unless $hierarchy;

  # check whether one of these categories contains the topics;
  # if one of the topics is a category itself, then test for subsumtion
  foreach my $catName (@{$this->{topics}}) {
    my $cat = $hierarchy->getCategory($catName);
    next unless $cat;    # not a category

    foreach my $topic (@$topics) {
      my @topicTypes = getCore()->getTopicTypes($web, $topic);
      if (@topicTypes && grep { /^Category$/ } @topicTypes) {
        # ignoring changes in category topics themselves
        # SMELL: make this configurable
        next;
      }
      if ($cat->contains($topic) || $cat->subsumes($topic)) {
        $found = 1;
        last;
      }
    }
    last if $found;
  }

  return $found;
}

=begin TML

---++ restUpdateCache()

REST handler to create and update the hierarchy cache

=cut

sub restUpdateCache {
  my $session = shift;

  my $request = Foswiki::Func::getRequestObject();

  my $theWeb = $request->param('web');
  my $theDebug = Foswiki::Func::isTrue($request->param('debug'), 0);
  my @webs;

  $request->param("refresh", "cat");

  if ($theWeb) {
    push @webs, $theWeb;
  } else {
    @webs = Foswiki::Func::getListOfWebs();
  }

  foreach my $web (sort @webs) {
    print STDERR "refreshing $web\n" if $theDebug;
    getHierarchy($web);
  }
}

1;
