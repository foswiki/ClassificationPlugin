# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2017 Michael Daum http://michaeldaumconsulting.com
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

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Contrib::DBCacheContrib::Search ();
use Foswiki::Request();

BEGIN {
    # Backwards compatibility for Foswiki 1.1.x
    unless ( Foswiki::Request->can('multi_param') ) {
        no warnings 'redefine';
        *Foswiki::Request::multi_param = \&Foswiki::Request::param;
        use warnings 'redefine';
    }
}

our $VERSION = '6.00';
our $RELEASE = '23 Jan 2017';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'A topic classification plugin and application';

our $jsTreeConnector;
our $core;
our $services;
our $css = '<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ClassificationPlugin/styles.css" media="all" />';
our $origSubscriptionMatches;

BEGIN {
  # monkey-patch MailerContrib
  require Foswiki::Contrib::MailerContrib::Subscription;

  no warnings 'redefine';
  $origSubscriptionMatches = \&Foswiki::Contrib::MailerContrib::Subscription::matches;
  *Foswiki::Contrib::MailerContrib::Subscription::matches = \&Foswiki::Plugins::ClassificationPlugin::subscriptionMatches;
  use warnings 'redefine';
};
  
###############################################################################
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

  # WARNING: use SolrPlugin instead
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
    unless (defined $jsTreeConnector) {
      require Foswiki::Plugins::ClassificationPlugin::JSTreeConnector;
      $jsTreeConnector = Foswiki::Plugins::ClassificationPlugin::JSTreeConnector->new();
    }
    $jsTreeConnector->dispatchAction(@_);
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
    validate => 0,
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
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('updateCache', \&restUpdateCache, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name=>'SUBSUMES', 
    prec=>4,
    arity=>2,
    exec=>\&OP_subsumes,
  );
  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name=>'ISA', 
    prec=>4,
    arity=>2,
    exec=>\&OP_isa,
  );
  Foswiki::Contrib::DBCacheContrib::Search::addOperator(
    name=>'DISTANCE', 
    prec=>5,
    arity=>2,
    exec=>\&OP_distance,
  );

  Foswiki::Func::addToZone('head', 'CLASSIFICATIONPLUGIN::CSS', $css, 'JQUERYPLUGIN::FOSWIKI');

  if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(\&indexTopicHandler);
    Foswiki::Plugins::SolrPlugin::registerIndexAttachmentHandler(\&indexAttachmentHandler);
  }

  $core = undef;
  $services = undef;
  $jsTreeConnector = undef;

  return 1;
}

###############################################################################
sub indexTopicHandler {
  return getCore()->indexTopicHandler(@_);
}

###############################################################################
sub indexAttachmentHandler {
  return getCore()->indexAttachmentHandler(@_);
}

###############################################################################
sub getCore {

  unless (defined $core) {
    require Foswiki::Plugins::ClassificationPlugin::Core;
    $core = Foswiki::Plugins::ClassificationPlugin::Core->new();
  }

  return $core;
}

###############################################################################
sub getServices {

  unless (defined $services) {
    require Foswiki::Plugins::ClassificationPlugin::Services;
    $services = Foswiki::Plugins::ClassificationPlugin::Services->new();
  }

  return $services;
}

###############################################################################
sub beforeSaveHandler {
  return getCore()->beforeSaveHandler(@_);
}

###############################################################################
sub afterSaveHandler {
  return getCore()->afterSaveHandler(@_);
}

###############################################################################
sub afterRenameHandler {
  return getCore()->afterRenameHandler(@_);
}

###############################################################################
sub finishPlugin {

  getCore()->finish(@_) if defined $core;
  $core = undef;

  getServices()->finish(@_) if defined $services;
  $services = undef;
}

###############################################################################
# perl api
sub getHierarchy {
  return getCore()->getHierarchy(@_);
}

###############################################################################
sub getHierarchyFromTopic {
  return getCore()->getHierarchyFromTopic(@_);
}

###############################################################################
sub getHierarchyFromText {
  return getCore()->getHierarchyFromText(@_);
}


###############################################################################
sub OP_subsumes {
  return getCore()->OP_subsumes(@_);
}

###############################################################################
sub OP_isa {
  return getCore()->OP_isa(@_);
}

###############################################################################
sub OP_distance {
  return getCore()->OP_distance(@_);
}

###############################################################################
# this is our impl of Foswiki::Contrib::MailerContrib::Subscription::matches()
# to implement subscription to a category: notify about changes of any topic
# covered by a category the user is subscribed to
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
    next unless $cat; # not a category

    foreach my $topic (@$topics) {
      my @topicTypes = getCore()->getTopicTypes($web, $topic);        
      if (@topicTypes && grep(/^Category$/, @topicTypes)) {
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

###############################################################################
# REST handler to create and update the hierarchy cache
sub restUpdateCache {
  my $session = shift;

  my $request = Foswiki::Func::getRequestObject();

  my $theWeb = $request->param('web');
  my $theDebug = Foswiki::Func::isTrue($request->param('debug'), 0);
  my @webs;

  $request->param("refresh", "cat");

  if ($theWeb) {
    push @webs,$theWeb;
  } else {
    @webs = Foswiki::Func::getListOfWebs();
  }


  foreach my $web (sort @webs) {
    print STDERR "refreshing $web\n" if $theDebug;
    getHierarchy($web);
  }
}

1;
