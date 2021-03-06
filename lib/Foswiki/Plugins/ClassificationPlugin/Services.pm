# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2019 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ClassificationPlugin::Services;

use strict;
use warnings;

our $debug = 0;
use Foswiki::Plugins::DBCachePlugin ();
use Foswiki::Plugins::ClassificationPlugin();
use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();
use Foswiki::Form ();
use JSON ();

# JSON-RPC error codes
# Error codes for json-rpc response
# -32601: unknown action
# -32600: method not allowed
# 0: ok
# 1: unknown error
# 100: no from value
# 200: access to service not allowed
# 300: web does not exist
# 400: missing parameter
# 500: form definition not found
# 600: unknwon category
# 700: invalid map format
# 800: topic has got an unknown category
# 900: oops, not mapped onto any facet


###############################################################################
sub new {
  my $class = shift;

  my $this = bless({
    @_
  }, $class);

  return $this;
}

###############################################################################
sub finish {
  # a nop for now
}

###############################################################################
sub printJSONRPC {
  my ($this, $response, $code, $text, $id) = @_;

  $response->header(
    -status  => $code?500:200,
    -type    => 'text/plain',
  );

  $id = 'id' unless defined $id;

  my $message;
  
  if ($code) {
    $message = {
      jsonrpc => "2.0",
      error => {
        code => $code,
        message => $text,
        id => $id,
      }
    };
  } else {
    $message = {
      jsonrpc => "2.0",
      result => ($text?$text:'null'),
      id => $id,
    };
  }

  $message = JSON::to_json($message, {pretty=>1});
  $response->print($message);
}

###############################################################################
sub normalizeTags {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $query = Foswiki::Func::getRequestObject();
  my $theWeb = $query->param('web') || $session->{webName};
  $theWeb = Foswiki::Sandbox::untaintUnchecked($theWeb);

  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($theWeb);
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($theWeb);

  my @topicNames = sort $db->getKeys();
  my $user = Foswiki::Func::getWikiName();
  my %knownTags;
  my %foundTopics;
  foreach my $topic (@topicNames) {
    my $tags = $hierarchy->getTagsOfTopic($topic);
    next unless $tags;
    foreach my $tag (@$tags) {
      push @{$knownTags{$tag}}, $topic;
      $foundTopics{$topic} = 1;
    }
  }
  my @foundTopics = keys %foundTopics;
  my $foundTags = 0;
  foreach my $tag (sort keys %knownTags) {
    my $altTag = $tag;
    $altTag =~ s/[^a-zA-Z0-9]//g;
    next if $altTag eq $tag;
    $foundTags++;
    next unless $knownTags{$altTag};
    my $count = Foswiki::Plugins::ClassificationPlugin::getCore()->renameTag($altTag, $tag, $theWeb, \@foundTopics);
    #print "renamed $count topics while changing $altTag to $tag\n";
  }
  my $totalTags = scalar(keys %knownTags);
  my $foundTopics = scalar(@foundTopics);

  if ($foundTopics) {
    $this->printJSONRPC($response, 0, "Successfully rename $foundTags of $totalTags tags in $foundTopics topics");
  } else {
    $this->printJSONRPC($response, 0, "No tags found");
  }

  return;
}

###############################################################################
# rename a tag: 
#
# parameters
#    * from: old tag name
#    * to: new tag name
sub renameTag {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $query = Foswiki::Func::getRequestObject();
  my $theWeb = $query->param('web') || $session->{webName};
  $theWeb = Foswiki::Sandbox::untaintUnchecked($theWeb);

  unless (Foswiki::Func::webExists($theWeb)) {
    $this->printJSONRPC($response, 300, "web does not exist");
    return;
  }

  my @theFrom = $query->param('from');

  my $theTo = $query->param('to') || '';
  $theTo = Foswiki::Sandbox::untaintUnchecked($theTo);

  my @from;
  foreach my $from (@theFrom) {
    next unless $from;
    $from = Foswiki::Sandbox::untaintUnchecked($from);
    push @from, $from;
  }
  unless (@from) {
    $this->printJSONRPC($response, 100, "undefined 'from' parameter");
    return;
  }

  my $count = Foswiki::Plugins::ClassificationPlugin::getCore()->renameTag(\@from, $theTo, $theWeb);

  if ($count) {
    $this->printJSONRPC($response, 0, "Successfully renamed $count topics");
  } else {
    $this->printJSONRPC($response, 0, "Nothing to rename");
  }

  return;
}

###############################################################################
# convert all topics of a TopicType to a newly created TopicType by splitting
# and distributing its facets onto newly named formfields. For example
# a Category field might hold categories of different kind. You can now
# replace the Category formfield with new ones Facet1 and Facet2 and split
# the set of categories stored in the former Category field and move them
# to Facet1 or Facet2
#
# Parameters:
#    * web: the web to process, defaults to baseWeb
#    * intopictype: input TopicType, the set of topics to be processed
#    * outtopictype: optionally change the TopicType after having split the facet
#    * form: new DataForm to be used for converted topics
#    * map: list of formfield=category items that specify the list of new facets
#           and their root node in the taxonomy
# Note: this is an admin service - only users in the AdminGroup are allowed to call it
sub splitFacet {
  my ($this, $session, $subject, $verb, $response) = @_;

  unless (Foswiki::Func::isAnAdmin()) {
    $this->printJSONRPC($response, 200, "access to service not allowed");
    return;
  }

  my $query = Foswiki::Func::getRequestObject();
  $debug = Foswiki::Func::isTrue($query->param('debug'), 0);

  my $theWeb = $query->param('web') || $session->{webName};
  $theWeb = Foswiki::Sandbox::untaintUnchecked($theWeb);

  unless (Foswiki::Func::webExists($theWeb)) {
    $this->printJSONRPC($response, 300, "web does not exist");
    return;
  }

  my $theInTopicType = $query->param('intopictype');
  unless (defined $theInTopicType) {
    $this->printJSONRPC($response, 400, "parameter intopictype required");
    return;
  }

  my $theOutTopicType = $query->param('outtopictype') || $theInTopicType;
  my $theExcludeTopicType = $query->param('excludetopictype');

  my $theNewForm = $query->param('form');
  unless (Foswiki::Func::topicExists(undef, $theNewForm)) {
    $this->printJSONRPC($response, 500, "form definition not found");
    return;
  }

  my $theMap = $query->param('map');
  unless (defined $theMap) {
    $this->printJSONRPC($response, 400, "parameter map required");
    return;
  }

  _writeDebug("opening web '$theWeb'");
  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($theWeb);
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($theWeb);

  my %map = ();
  foreach my $mapItem (split(/\s*,\s*/, $theMap)) {
    if ($mapItem =~ /^(.*)=(.*)$/) {
      my $fieldName = $1;
      my $categoryName = $2;
      my $cat = $hierarchy->getCategory($categoryName);
      unless ($cat) {
        $this->printJSONRPC($response, 600, "unknwon category");
        return;
      }

      _writeDebug("mapping facet '$fieldName' to '$categoryName'");
      $map{$fieldName} = $cat;
    } else {
      $this->printJSONRPC($response, 700, "invalid map format");
      return;
    }
  }

  my @topicNames = sort $db->getKeys();
  my $foundTopics = 0;
  my $index = 0;
  foreach my $topicName (@topicNames) {
    my $topicObj = $db->fastget($topicName);

    my $form = $topicObj->fastget("form");
    next unless $form;

    $form = $topicObj->fastget($form);
    next unless $form;

    my $topicTypes = $form->fastget('TopicType');
    next unless $topicTypes;

    next unless $topicTypes =~ /\b$theInTopicType\b/;
    if ($theExcludeTopicType && $topicTypes =~ /$theExcludeTopicType/)  {
      _writeDebug("excluding $topicName because '$topicTypes matches' '$theExcludeTopicType'");
      next;
    }

    my $cats = $hierarchy->getCategoriesOfTopic($topicObj);
    next unless $cats;

    $foundTopics++;
    _writeDebug("$foundTopics: reading $topicName ... cats=@$cats");
    my %facets = ();
    foreach my $catName (@$cats) {
      my $cat = $hierarchy->getCategory($catName);
      unless ($cat) {
	$this->printJSONRPC($response, 800, "topic has got an unknown category");
        return;
      }
      my $foundFacet = 0;
      foreach my $facet (keys %map) {
	if ($map{$facet}->subsumes($cat)) {
	  push @{$facets{$facet}}, $catName;
	  $foundFacet = 1;
	  last;
	}
      }
      unless ($foundFacet) {
        $this->printJSONRPC($response, 900, "oops, category not mapped onto any facet");
        return;
      }
    }
  
    my ($meta, $text) = Foswiki::Func::readTopic($theWeb, $topicName);
    #_writeDebug("OLD meta:\n".$meta->stringify());
    
    if (%facets) {
      if ($debug) {
	my $message = '';
	foreach my $facet (sort keys %facets) {
	  $message .= "\n  $facet=".join(', ', @{$facets{$facet}});
	}
	_writeDebug("$topicName facets: $message");
      }

      foreach my $facet (sort keys %facets) {
	$meta->putKeyed('FIELD', {
	  name => $facet,
	  title => $facet,
          value => join(', ', @{$facets{$facet}}),
	});
      }
    }
    if ($theInTopicType ne $theOutTopicType) {
      $meta->putKeyed('FIELD', {
	name => 'TopicType',
	title => 'TopicType',
	value => $theOutTopicType,
      });
    }
    if (defined $theNewForm) {
      my $formDef = $meta->get('FORM');
      $formDef->{name} = $theNewForm;
    }
    #_writeDebug("NEW meta:\n".$meta->stringify());

    Foswiki::Func::saveTopic($theWeb, $topicName, $meta, $text);
  }

  return "OK: converted $foundTopics topics\n";
}

###############################################################################
sub deployTopicType {
  my ($this, $session, $subject, $verb, $response) = @_;

  unless (Foswiki::Func::getContext()->{command_line}) {
    print STDERR "ERROR: can only be called from the commandline\n";
    return;
  }

  my $query = Foswiki::Func::getRequestObject();

  $debug = Foswiki::Func::isTrue($query->param('debug'), 0);
  my $dry = Foswiki::Func::isTrue($query->param('dry'), 0);

  _writeDebug("Warning: THIS IS A DRY RUN") if $dry;

  my $includeWebs = $query->param('includeweb') || '.*';
  my $includeWebPattern = '^('.join("|", split(/\s*,\s*/, $includeWebs)).')$';
  _writeDebug("includeWebPattern=$includeWebPattern");

  my $excludeWebs = $query->param('excludeweb') || '';
  my @excludeWebs = split(/\s*,\s*/, $excludeWebs);
  push @excludeWebs, '_.*', '.*/_.*', 'System', 'Trash', 'Applications.*';
  my $excludeWebPattern = '^('.join("|", @excludeWebs).')$';
  _writeDebug("excludeWebPattern=$excludeWebPattern");

  my $includeTopics = $query->param('includetopic') || '.*';
  my $includeTopicPattern = '^('.join("|", split(/\s*,\s*/, $includeTopics)).')$';
  _writeDebug("includeTopicPattern=$includeTopicPattern");

  my $excludeTopics = $query->param('excludetopic') || '';
  my @excludeTopics = split(/\s*,\s*/, $excludeTopics);
  push @excludeTopics, 'WebPreferences','WebIndex','WebTopicList','WebStatistics','WebChanges','WebNotify','WebTreeView','WebSearch.*','WebRss','WebAtom','.*Template';
  my $excludeTopicPattern = '^('.join("|", @excludeTopics).')$';
  _writeDebug("excludeTopicPattern=$excludeTopicPattern");

  my $dataForm = $query->param('form') || 'Applications.ClassificationApp.ClassifiedTopic';
  $dataForm =~ s/\\/\./g;
  my ($dataFormWeb, $dataFormTopic) = Foswiki::Func::normalizeWebTopicName('', $dataForm);
  
  return "ERROR: $dataForm does not exist\n\n" unless Foswiki::Func::topicExists($dataFormWeb, $dataFormTopic);

  my $formDef = new Foswiki::Form($session, $dataFormWeb, $dataForm);
  return "ERROR: no form at $dataForm\n\n" unless defined $formDef;

  my $deleteForms = $query->param('deleteform');
  my $deleteFormPattern;
  if (defined $deleteForms) {
    $deleteFormPattern = '^('.join("|", split(/\s*,\s*/, $deleteForms)).')$';
    _writeDebug("deleteFormPattern=$deleteFormPattern");
  }

  my $excludeForms = $query->param('excludeform') || '';
  my @excludeForms = split(/\s*,\s*/, $excludeForms);
  push @excludeForms, $dataForm;
  push @excludeForms, '.*UserForm'; ### SMELL
  my $excludeFormPattern = '^('.join("|", @excludeForms).')$';
  _writeDebug("excludeFormPattern=$excludeFormPattern");

  my @webs = grep { /$includeWebPattern/ && !/$excludeWebPattern/ } Foswiki::Func::getListOfWebs();
  _writeDebug("found ".scalar(@webs)." web(s)");
  #_writeDebug("webs=".join("\n", @webs));

  Foswiki::Plugins::DBCachePlugin::disableSaveHandler();
  Foswiki::Plugins::DBCachePlugin::disableRenameHandler();

  my $nrTopics = 0;
  foreach my $web (@webs) {
    _writeDebug("processing web $web");
    my @topics = grep {/$includeTopicPattern/ && !/$excludeTopicPattern/} Foswiki::Func::getTopicList($web);
    _writeDebug("found ".scalar(@topics)." topic(s) in web $web");

    # add form to WEBFORMS in WebPreferences
    my ($meta, $text) = Foswiki::Func::readTopic($web, "WebPreferences");
    if (defined $meta) {
      my %webForms = ();
      my $needsSave = 0;
      if ($text =~ /^(   )+\* Set WEBFORMS =\s+(.*?)\s*$/ms) {
        %webForms = map {s/\//\./g; $_ => 1} grep {!/$deleteFormPattern/} split(/\s*,\s*/, $2);
        #_writeDebug("found ".scalar(keys %webForms)." webform(s)");
        if (defined $webForms{$dataForm}) {
          #_writeDebug("dataForm already part of WEBFORMS");
        } else {
          $webForms{$dataForm} = 1;
          _writeDebug("adding $dataForm");
          my $webForms = join(", ", keys %webForms);
          $text =~ s/^(   +\* Set WEBFORMS =)\s+(.*?)$/$1 $webForms/ms;
          $needsSave = 1;
        }
      } else {
        _writeDebug("no webforms found yet ... creating them");
        $text .= "\n   * Set WEBFORMS = $dataForm\n";
        $needsSave = 1;
      }
      Foswiki::Func::saveTopic($web, "WebPreferences", $meta, $text, {
        ignorepermissions => 1,
        dontlog => 1,
        minor => 1,
      }) unless $dry;
    } else {
      _writeDebug("woops, error reading $web.WebPreferences");
    }

    # install topic stup for WikiWorkbench TopicTypes
    my $topicStub = $dataForm;
    $topicStub =~ s/.*\.//;
    unless (Foswiki::Func::topicExists($web, $topicStub)) {
      _writeDebug("creating topicStub $web.$topicStub");

      #SMELL: make this configurable
      my ($meta, $text) = Foswiki::Func::readTopic($web, $topicStub);
      $meta->put("FORM", {name=>"Applications.TopicStub"});
      $meta->put("FIELD", {name=>"TopicType", title=>"TopicType", value=>"TopicStub, TopicType"});
      $meta->put("FIELD", {name=>"Target", attributes=>"", title=>"Target", value=>"Applications/ClassificationApp.ClassifiedTopic"});
      Foswiki::Func::saveTopic($web, $topicStub, $meta, $text, {
        ignorepermissions => 1,
        dontlog => 1,
        minor => 1,
      }) unless $dry;

    } else {
      _writeDebug("topicStub $web.$topicStub already exists");
    }

    foreach my $topic (@topics) {

      my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
      my $formName = $meta->getFormName;
      if (defined $formName) {
        if ($formName =~ /$excludeFormPattern/) {
          #_writeDebug("... skipping topic $web.$topic with form $formName");
          next;
        }
        if (defined $deleteFormPattern && $formName =~ /$deleteFormPattern/) {
          #_writeDebug("... deleting form $formName");
          $meta->remove("FORM");
          $meta->remove("FIELD");
        } else {

          # Remove fields that don't exist on the new form def.
          my $filter = join( '|',
              map  { $_->{name} }
              grep { $_->{name} } @{ $formDef->getFields() } );

          foreach my $f ($meta->find('FIELD')) {
            if ($f->{name} !~ /^($filter)$/) {
              #_writeDebug("removing field $f->{name}");
              $meta->remove('FIELD', $f->{name} );
            } else {
              #_writeDebug("reusing field $f->{name}");
            }
          }
        }

      } else {
        #_writeDebug("no form at $web.$topic yet ...");
      }
      _writeDebug("$nrTopics: processing topic $web.$topic");

      #_writeDebug("adding form $dataForm");
      $meta->put('FORM', { name => $dataForm });

      my $topicTitle = Foswiki::Plugins::Func::getTopicTitle($web, $topic, undef, $meta);
      if (defined $topicTitle) {
        $meta->remove('PREFERENCE', 'TOPICTITLE');
        $meta->putKeyed( 'FIELD', { 
          name => 'TopicTitle', 
          title => '<nop>TopicTitle', 
          value => $topicTitle
        });
      }

      if (0) {
        ### saveTopic is too slow on lots of data

        # tricking in last author
        my $topicInfo = $meta->get("TOPICINFO");
        my $lastAuthor;
        $lastAuthor = $topicInfo->{author} if $topicInfo;

        unless (defined $lastAuthor) {
          #_writeDebug("woops no proper TOPICINFO in $web.$topic");
          $lastAuthor = "UnknownUser";
        }

        my $origCUID = $session->{user};
        $session->{user} = $lastAuthor;
        Foswiki::Func::saveTopic($web, $topic, $meta, $text, {
          ignorepermissions => 1,
          dontlog => 1,
          minor => 1,
        }) unless $dry;
        $session->{user} = $origCUID;
      } else {
        # using raw file access for speed

        my $nuText = $meta->getEmbeddedStoreForm();
        my $webDir = $meta->web;
        $webDir =~ s/\./\//g;
        my $topicFile = $Foswiki::cfg{DataDir}.'/'.$webDir.'/'.$topic.'.txt';

        #_writeDebug("topicFile=$topicFile");
        if (-e $topicFile) {
          Foswiki::Func::saveFile($topicFile, $nuText) unless $dry;
        } else {
          print STDERR "ERROR: file for $web.$topic not found at $topicFile\n";
        }
      }
    
      $nrTopics++;
    } # end of foreach topic
  } # end of foreach web

  _writeDebug("converted $nrTopics topic(s)");

  Foswiki::Plugins::DBCachePlugin::enableSaveHandler();
  Foswiki::Plugins::DBCachePlugin::enableRenameHandler();

  return;
}

###############################################################################
# statics
###############################################################################
sub _writeDebug {
  print STDERR $_[0]."\n" if $debug;
  #Foswiki::Func::writeDebug('- ClassificationPlugin::Services - '.$_[0]) if $debug;
}

1;
