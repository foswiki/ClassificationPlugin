# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2014 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Contrib::DBCacheContrib::Search ();

our $VERSION = '3.30';
our $RELEASE = '3.30';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'A topic classification plugin and application';

our $jsTreeConnector;

our $doneInitCore;
our $doneInitServices;
our $baseTopic;
our $baseWeb;
our $css = '<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ClassificationPlugin/styles.css" media="all" />';
  
###############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  Foswiki::Func::registerTagHandler('HIERARCHY', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleHIERARCHY(@_);
  });

  Foswiki::Func::registerTagHandler('ISA', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleISA(@_);
  });

  Foswiki::Func::registerTagHandler('SUBSUMES', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleSUBSUMES(@_);
  });

  # WARNING: use SolrPlugin instead
  Foswiki::Func::registerTagHandler('SIMILARTOPICS', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleSIMILARTOPICS(@_);
  });

  Foswiki::Func::registerTagHandler('CATINFO', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleCATINFO(@_);
  });

  Foswiki::Func::registerTagHandler('TAGINFO', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleTAGINFO(@_);
  });

  Foswiki::Func::registerTagHandler('DISTANCE', sub {
    initCore();
    return Foswiki::Plugins::ClassificationPlugin::Core::handleDISTANCE(@_);
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
    initServices();
    return Foswiki::Plugins::ClassificationPlugin::Services::splitFacet(@_);
  }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('renametag', sub {
      initServices();
      return Foswiki::Plugins::ClassificationPlugin::Services::renameTag(@_);
    }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'POST',
  );

  Foswiki::Func::registerRESTHandler('normalizetags', sub {
    initServices();
    return Foswiki::Plugins::ClassificationPlugin::Services::normalizeTags(@_);
  }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'POST',
  );

  Foswiki::Func::registerRESTHandler('deployTopicType', sub {
    initServices();
    return Foswiki::Plugins::ClassificationPlugin::Services::deployTopicType(@_);
  }, 
    authenticate => 1,
    validate => 0,
    http_allow => 'POST',
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

  # SMELL this is not reliable as it depends on plugin order
  # if (Foswiki::Func::getContext()->{SolrPluginEnabled}) {
  if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(\&indexTopicHandler);
    Foswiki::Plugins::SolrPlugin::registerIndexAttachmentHandler(\&indexAttachmentHandler);
  }

  $doneInitCore = 0;
  $doneInitServices = 0;
  $jsTreeConnector = undef;
  return 1;
}

###############################################################################
sub indexTopicHandler {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::indexTopicHandler(@_);
}

###############################################################################
sub indexAttachmentHandler {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::indexAttachmentHandler(@_);
}

###############################################################################
sub initCore {
  return if $doneInitCore;
  $doneInitCore = 1;
  require Foswiki::Plugins::ClassificationPlugin::Core;
  Foswiki::Plugins::ClassificationPlugin::Core::init($baseWeb, $baseTopic);

#  require Foswiki::Plugins::ClassificationPlugin::Access;
#  Foswiki::Plugins::ClassificationPlugin::Access::init($baseWeb, $baseTopic);
}

###############################################################################
sub initServices {
  return if $doneInitServices;
  $doneInitServices = 1;

  initCore();

  require Foswiki::Plugins::ClassificationPlugin::Services;
  Foswiki::Plugins::ClassificationPlugin::Services::init($baseWeb, $baseTopic);
}

###############################################################################
sub beforeSaveHandler {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::beforeSaveHandler(@_);
}

###############################################################################
sub afterSaveHandler {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::afterSaveHandler(@_);
}

###############################################################################
sub afterRenameHandler {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::afterRenameHandler(@_);
}

###############################################################################
sub finishPlugin {

  Foswiki::Plugins::ClassificationPlugin::Core::finish(@_)
    if $doneInitCore;
  Foswiki::Plugins::ClassificationPlugin::Services::finish(@_)
    if $doneInitServices;
}

###############################################################################
# perl api
sub getHierarchy {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::getHierarchy(@_);
}

###############################################################################
sub OP_subsumes {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::OP_subsumes(@_);
}

###############################################################################
sub OP_isa {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::OP_isa(@_);
}

###############################################################################
sub OP_distance {
  initCore();
  return Foswiki::Plugins::ClassificationPlugin::Core::OP_distance(@_);
}

1;
