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

package Foswiki::Plugins::ClassificationPlugin::Hierarchy;

use strict;
use warnings;

use Foswiki::Plugins::DBCachePlugin ();
use Foswiki::Plugins::ClassificationPlugin ();
use Foswiki::Plugins::ClassificationPlugin::Core ();
use Foswiki::Plugins::ClassificationPlugin::Category ();
use Storable ();
use Foswiki::Prefs ();
use Foswiki::Func ();
use JSON ();
use Carp qw(cluck confess);

use constant OBJECTVERSION => 0.92;
use constant CATWEIGHT => 1.0; # used in computeSimilarity()
use constant TRACE => 0; # toggle me

our %insideInit;

###############################################################################
# static
sub writeDebug {
  print STDERR '- ClassificationPlugin::Hierarchy - '.$_[0]."\n" if TRACE;
}

################################################################################
# constructor
sub new {
  my $class = shift;
  my $web = shift;
  my $topic = shift;
  my $text = shift;

  my $this;
  my $session = $Foswiki::Plugins::SESSION;
  my $query = Foswiki::Func::getCgiQuery();

  if (defined $web) {
    $web =~ s/\//\./g;
    my $cacheFile = Foswiki::Plugins::ClassificationPlugin::getCore()->getCacheFile($web, $topic);
    
    my $refresh = '';
    $refresh = $query->param('refresh') || '' if defined $session;
    $refresh = ($refresh =~ /on|class|cat/)?1:0;

    unless ($refresh) {
      eval {
        $this = Storable::lock_retrieve($cacheFile);
      };
    }

    if ($this && $this->{_version} == OBJECTVERSION) {
      writeDebug("restored hierarchy object (v$this->{_version}) from $cacheFile");
      #if (TRACE) {
      #  use Data::Dumper;
      #  writeDebug(Dumper($this));
      #}
      return $this;
    } else {
      writeDebug("creating new object");
    }
  } else {
    $web = '_virtual';
  }

  $this = {
    web=>$web,
    topic => $topic,
    text => $text,
    idCounter=>0,
    @_
  };

  $this = bless($this, $class);
  $this->init();
  $this->{gotUpdate} = 1;
  $this->{_version} = OBJECTVERSION;

  return $this;
}

################################################################################
# does not invalidate this object; it is kept intact to be cached in memory
# in a mod_perl or speedy-cgi setup; we only store it to disk if we updated it 
sub finish {
  my $this = shift;

  writeDebug("called finish()");
  my $gotUpdate = $this->{gotUpdate};
  $this->{gotUpdate} = 0;

  if (defined($this->{_categories})) {
    foreach my $cat ($this->getCategories()) {
      $gotUpdate ||= $cat->{gotUpdate};
      $cat->{gotUpdate} = 0;

    }
  }

  return if $this->{web} eq '_virtual';

  my $key = $this->{web};
  $key .= '.'.$this->{topic} if defined $this->{topic};

  writeDebug("gotUpdate=$gotUpdate");
  if ($gotUpdate) {
    my $cacheFile = Foswiki::Plugins::ClassificationPlugin::getCore()->getCacheFile($key);
    writeDebug("saving hierarchy $this->{web} to $cacheFile");

    # don't cache the prefs 
    undef $this->{_prefs}; 

    # dont' cache translations
    undef $this->{_translate};

    #if (TRACE) {
    #  use Data::Dumper;
    #  writeDebug(Dumper($this));
    #}

    Storable::lock_store($this, $cacheFile);
  }
  writeDebug("done finish()");

}

################################################################################
# mode = 0 -> do nothing
# mode = 1 -> a tagged topic has been saved
# mode = 2 -> a categorized topic has been saved
# mode = 3 -> a classified topic has been saved
# mode = 4 -> a category has been saved
# mode = 5 -> clear all
sub purgeCache {
  my ($this, $mode, $touchedCats) = @_;

  return unless $mode;
  writeDebug("purging hierarchy cache for $this->{web} - mode = $mode");

  if ($mode == 1 || $mode == 3 || $mode > 4) { # tagged and classified topics
    undef $this->{_similarity};
  } 

  if ($mode > 1) { # categorized and classified topics
    foreach my $catName (@$touchedCats) {
      my $cat = $this->getCategory($catName);
      $cat->purgeCache() if $cat;
      undef $this->{_catsOfTopic};
    }
    $this->{_top}->purgeCache() if $this->{_top};
    $this->{_bottom}->purgeCache() if $this->{_bottom};
  } 

  if ($mode > 3) { # category topics
    # nuke all categories
    writeDebug("nuke all categories");
    foreach my $cat (values %{$this->{_categories}}) {
      $cat->purgeCache() if $cat;
    }
    undef $this->{_categories};
    undef $this->{_distance};
    undef $this->{_prefs};
    undef $this->{_translate};
    undef $this->{_top};
    undef $this->{_top};
    undef $this->{_bottom};
    undef $this->{_aclAttribute};
    $this->{idCounter} = 0;
  }

  if ($mode > 4) { # clear all of the rest
    undef $this->{_catFields};
    undef $this->{_tagFields};
  }

  $this->{gotUpdate} = 1;
}

################################################################################
sub init {
  my $this = shift;

  my $key = $this->{web};
  $key .= '.'.$this->{topic} if defined $this->{topic};

  # be anal
  die "recursive call to Hierarchy::init for $key" if $insideInit{$key};
  $insideInit{$key} = 1;

  writeDebug("called Hierarchy::init for $key ... EXPENSIVE");

  # reset all
  $this->purgeCache(5);

  # init from a topic
  if ($this->{topic}) {
    unless ($this->initFromTopic) {
      delete $insideInit{$key};
      return;
    }
  } 

  # init from text
  elsif ($this->{text}) {
    unless ($this->initFromText) {
      return;
    }
  } 

  # default
  else {
    unless ($this->initFromWeb) {
      delete $insideInit{$key};
      return;
    }
  }

  writeDebug("checking for default categories");
  # every hierarchy has one top node
  my $topCat = 
    $this->{_categories}{'TopCategory'} || 
    $this->createCategory('TopCategory', title=>'Top', origWeb=>'');

  # every hierarchy has one bottom node
  my $bottomCat = 
    $this->{_categories}{'BottomCategory'} ||
    $this->createCategory('BottomCategory', title=>'Bottom', origWeb=>'');

  # remember these
  $this->{_top} = $topCat;
  $this->{_bottom} = $bottomCat;

  # init nested structures
  foreach my $cat (values %{$this->{_categories}}) {
    $cat->init();
  }

  # add categories with no children as a parent to BottomCategory
  my @bottomParents = ();
  foreach my $cat (values %{$this->{_categories}}) {
    next if $cat->getChildren() || $cat == $bottomCat;
    $cat->addChild($bottomCat);
    push @bottomParents, $cat;
  }
  $bottomCat->setParents(@bottomParents);

  # init these again
  foreach my $cat (@bottomParents) {
    $cat->init();
  }

  $this->{gotUpdate} = 1;

  if (0) {
    foreach my $cat (values %{$this->{_categories}}) {
      my $text = "$cat->{name}:";
      foreach my $child ($cat->getChildren()) {
	$text .= " $child->{name}";
      }
      print STDERR $text."\n";
    }
    #$this->printDistanceMatrix();
  }

  writeDebug("done init $key");
  delete $insideInit{$key};
}

################################################################################
sub initFromTopic {
  my $this = shift;

  my $key = $this->{web};
  $key .= '.'.$this->{topic} if defined $this->{topic};

  my ($meta, $text) = Foswiki::Func::readTopic($this->{web}, $this->{topic});

  return $this->initFromText($text);
}

################################################################################
sub initFromText {
  my $this = shift;

  # potentially create the list using macros
  my $web = $this->{web};
  my $topic = $this->{topic} || $Foswiki::cfg{HomeTopicName};

  my $text = Foswiki::Func::expandCommonVariables($this->{text}, $topic, $web);

  my $insideList = 0;
  my @list = ();
  my %lookup = ();
  foreach my $line ( split( /\r?\n/, $text ) ) {
    if ($line =~ /^((?:\t|   )+)\*\s+(.*?)\s*$/ ) {
      my $indent = $1;
      my $title = $2;
      $indent =~ s/\t/   /;
      $indent = length($indent) / 3;
      $insideList = 1;

      my $name = $title;
      $name =~ s/^\s*//;
      $name =~ s/\s*$//;
      $name = ucfirst($name);
      $name =~ s/[^$Foswiki::regex{mixedAlphaNum}]//g;
      $name =~ s/\s([$Foswiki::regex{mixedAlphaNum}])/\U$1/g;
      $name .= 'Category';

      $name = $this->{prefix}.$name if defined $this->{prefix};

      #print STDERR "indent=$indent, title='$title', name=$name\n";
      push @list, $lookup{$name} = {
        indent => $indent,
        title => $title,
        name => $name, 
      };
    } else {
      last if $insideList;
    }
  }

  # make it a hierarchy
  my $lastItem;
  my @root = ();
  foreach my $item (@list) {

    if ($item->{indent} == 1) {
      push @root, $item;
    }

    if ($lastItem) {

      # indent
      if ($item->{indent} > $lastItem->{indent}) {
        $item->{parent} = $lastItem;
      } 

      # outdent
      elsif ($item->{indent} < $lastItem->{indent}) {
        my $parent = $lastItem;
        for (my $i = $item->{indent}; $i <= $lastItem->{indent}; $i++) {
          $parent = $parent->{parent};
          last unless $parent;
        }
        $item->{parent} = $parent;
      } 

      # same level
      else {
        $item->{parent} = $lastItem->{parent};
      }
    } else {
      # first item
      $item->{parent} = undef;
    }

    $lastItem = $item;
  }

  my $order = 0;
  foreach my $item (@list) {
    my $cat = $this->createCategory($item->{name});
    my $parentName = $item->{parent}?$item->{parent}{name}:'TopCategory';

    $cat->setParents($parentName);
    $cat->title($item->{title});
    $cat->order($order++);
  }

  return 1;
}

################################################################################
sub initFromWeb {
  my $this = shift;

  my $key = $this->{web};

  my $session = $Foswiki::Plugins::SESSION;
  $this->{_prefs} = new Foswiki::Prefs($session);

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  unless ($db) {
    cluck("ERROR: can't get web for $this->{web}");
    return 0;
  }

  # iterate over all topics and collect categories
  my $seenImport = {};
  
  foreach my $topicName ($db->getKeys()) {
    my $topicObj = $db->fastget($topicName);
    next unless $topicObj;
    my $form = $topicObj->fastget("form");
    next unless $form;
    $form = $topicObj->fastget($form);
    next unless $form;

    # get topic types
    my $topicType = $form->fastget("TopicType");
    next unless $topicType;
    next unless $topicType =~ /\bCategory\b/;

    # this topic is a category in itself
    writeDebug("found category '$topicName' in web $key");
    my $cat = $this->{_categories}{$topicName};
    $cat = $this->createCategory($topicName) unless $cat;

    my $cats = $this->getCategoriesOfTopic($topicObj);
    if ($cats && @$cats) {
      $cat->setParents(@$cats);
    } else {
      $cat->setParents('TopCategory') if $cat->{name} ne 'TopCategory';
    }

    my $summary = $form->fastget("Summary") || '';
    $summary =~ s/<nop>//g;
    $summary =~ s/^\s+|\s+$//g;

    my $order = $form->fastget("Order");
    if (defined($order) && $order =~ /([+-]?\d+(?:\.\d)*)/) {
      $order = $1;
    } else {
      $order = 99999999;
    }

    my $title = $form->fastget("TopicTitle") || $topicName;
    $title =~ s/<nop>//g;
    $title =~ s/^\s+|\s+$//g;
    $cat->summary($summary);
    $cat->order($order);
    $cat->title($title);
    $cat->icon($form->fastget("Icon"));
    $cat->redirect($form->fastget("Redirect"));

    #writeDebug("$topicName has got title '$title'");

    # import foregin categories from another web
    my $impCats = $form->fastget("ImportedCategory");
    $cat->importCategories($impCats, $seenImport) if $impCats;

    my $text = $form->fastget("SubCategories");
    $cat->importCategoriesFromText($text, $this) if $text;
  }
  
  return 1;
}

################################################################################
sub printDistanceMatrix {
  return unless TRACE;

  my ($this) = @_;

  my $distance = $this->{_distance} || $this->computeDistance();

  foreach my $catName1 (sort $this->getCategoryNames()) {
    my $cat1 = $this->{_categories}{$catName1};
    my $catId1 = $cat1->{id};
    foreach my $catName2 (sort $this->getCategoryNames()) {
      my $cat2 = $this->{_categories}{$catName2};
      my $catId2 = $cat2->{id};
      my $dist =  $$distance[$catId1][$catId2];
      next unless $dist;
      writeDebug("distance($catName1/$catId1, $catName2/$catId2) = $dist");
    }
  }
}

################################################################################
# computes the distance between all categories using a Wallace-Kollias
# algorith for transitive closure
sub computeDistance {
  my $this = shift;

  my @distance;

  writeDebug("called computeDistance() Wallace-Kollias");

  my $topId = $this->{_top}->{id};
  $distance[$topId][$topId] = 0;

  my $bottomId = $this->{_bottom}->{id};
  $distance[$bottomId][$bottomId] = 0;

  # root of induction
  my %ancestors = ($topId=>$this->{_top});
  
  writeDebug("propagate");
  foreach my $child ($this->{_top}->getChildren()) {
    $distance[$topId][$child->{id}] = 1;
    $child->computeDistance(\@distance, \%ancestors);
  }

  writeDebug("finit");
  #my $loops = 0;
  my $maxId = $this->{idCounter}-1;
  for my $id1 (0..$maxId) {
    for my $id2 ($id1..$maxId) {
      next if $id1 == $id2;
      my $dist = $distance[$id1][$id2];
      if (defined($dist)) {
        $distance[$id2][$id1] = -$dist;
      } else {
        $dist = $distance[$id2][$id1];
        $distance[$id1][$id2] = -$dist if defined $dist;
      }
      #$loops++;
    }
  }

  #writeDebug("maxId=$maxId, loops=$loops");
  writeDebug("done computeDistance() Wallace-Kollias");

  #if (TRACE) {
  #  use Data::Dumper;
  #  writeDebug(Dumper(\@distance));
  #}

  $this->{_distance} = \@distance;
  $this->{gotUpdate} = 1;

  return \@distance;
}

################################################################################
# this computes the minimum distance between two categories or a topic
# and a category or between two topics. if a non-category topic is under
# consideration then all of its categories are measured against each other
# while computing the overall minimal distances.  so simplest case
# is measuring the distance between two categories; the most general case is
# computing the min distance between two sets of categories.
sub distance {
  my ($this, $topic1, $topic2) = @_;

  #writeDebug("called distance($topic1, $topic2)");

  my %catSet1 = ();
  my %catSet2 = ();

  # if topic1/topic2 are of type Category then they are the objects themselves
  # to be taken under consideration

  # check topic1
  my $catObj = $this->getCategory($topic1);
  my $firstIsTopic;
  if ($catObj) { # known category
    $firstIsTopic = 0;
    $catSet1{$topic1} = $catObj->{id};
  } else {
    $firstIsTopic = 1;
    my $cats = $this->getCategoriesOfTopic($topic1);
    return undef unless $cats; # no categories, no distance
    foreach my $name (@$cats) {
      $catObj = $this->getCategory($name);
      $catSet1{$name} = $catObj->{id} if $catObj;
    }
  }

  # check topic2
  my $secondIsTopic;
  $catObj = $this->getCategory($topic2);
  if ($catObj) { # known category
    $secondIsTopic = 0;
    $catSet2{$topic2} = $catObj->{id};
  } else {
    $secondIsTopic = 1;
    my $cats = $this->getCategoriesOfTopic($topic2);
    return undef unless $cats; # no categories, no distance
    foreach my $name (@$cats) {
      $catObj = $this->getCategory($name);
      $catSet2{$name} = $catObj->{id} if $catObj;
    }
  }
  return 0 if 
    $firstIsTopic == 1 &&
    $secondIsTopic == 1 &&
    $topic1 eq $topic2;

  if (TRACE) {
    #writeDebug("catSet1 = ".join(',', sort keys %catSet1));
    #writeDebug("catSet2 = ".join(',', sort keys %catSet2));
  }

  # get the min distance between the two category sets
  $this->computeDistance() unless $this->{_distance};
  my $distance = $this->{_distance};
  my $min;
  foreach my $id1 (values %catSet1) {
    foreach my $id2 (values %catSet2) {
      my $dist = $$distance[$id1][$id2];
      next unless defined $dist;
      $min = $dist if !defined($min) || abs($min) > abs($dist);
    }
  }

  # both sets aren't connected
  return undef if !defined($min) && $topic1 ne 'TopCategory' && $topic2 ne 'TopCategory';

  $min = abs($min) + 2 if $firstIsTopic && $secondIsTopic;
  $min-- if $firstIsTopic;
  $min++ if $secondIsTopic;

  return $min;
}

################################################################################
# fast lookup of the distance between two categories
sub catDistance {
  my ($this, $cat1, $cat2) = @_;

  my $id1;
  my $id2;
  my $cat1Obj = $cat1;
  my $cat2Obj = $cat2;

  if (ref($cat1)) {
    $id1 = $cat1->{id};
  } else {
    $cat1Obj = $this->getCategory($cat1);
    return undef unless defined $cat1Obj;
    $id1 = $cat1Obj->{id};
  }

  if (ref($cat2)) {
    $id2 = $cat2->{id};
  } else {
    $cat2Obj = $this->getCategory($cat2);
    return undef unless defined $cat2Obj;
    $id2 = $cat2Obj->{id};
  }

  $this->computeDistance() unless $this->{_distance};
  my $dist = $this->{_distance}[$id1][$id2];
  #writeDebug("catDistance($cat1Obj->{name}, $cat2Obj->{name})=$dist");
  return $dist;
}

################################################################################
# find all topics that are similar to the given one i nthe current web
# similarity is computed by calculating the weighted matching coefficient (WMC)
# counting matching tags and categories between two topics. matching categorization
# is weighted in a way to matter more, that is two topics correlate more if
# they are categorized similarly than if they do based on tagging information.
# this is an rought adhoc model to reflect the intuitive importance in 
# knowledge management of category information versus tagging information.
# the provided threshold limits the number of topics that are considered similar
#
sub getSimilarTopics {
  my ($this, $topicA, $threshold) = @_;

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  return () unless $db;

  my %wmc = ();
  my @foundTopics = ();
  my $tagsA = $this->getTagsOfTopic($topicA);
  my $catsA = $this->getCategoriesOfTopic($topicA);
  foreach my $topicB ($db->getKeys()) {
    next if $topicB eq $topicA;
    my $similarity = $this->computeSimilarity({
      topicA => $topicA, 
      topicB => $topicB, 
      tagsA => $tagsA, 
      catsA => $catsA
    });
    next if $similarity < $threshold;
    $wmc{$topicB} = $similarity;
    push @foundTopics, $topicB;
  }

  return wantarray ? (\@foundTopics, \%wmc) : \@foundTopics;
}

################################################################################
sub getSimilarTopicsOfTags {
  my ($this, $tags, $threshold) = @_;

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  return () unless $db;

  my %wmc = ();
  my @foundTopics = ();
  foreach my $topic ($db->getKeys()) {
    my $similarity = $this->computeSimilarity({
      topicA => $topic, 
      tagsB => $tags
    });
    next if $similarity < $threshold;
    $wmc{$topic} = $similarity;
    push @foundTopics, $topic if $similarity >= $threshold;
  }

  return wantarray ? (\@foundTopics, \%wmc) : \@foundTopics;
}

################################################################################
sub computeSimilarity {
  my ($this, $params) = @_;

  # lookup cache
  my $similarity;
  if (defined($params->{topicA}) && defined($params->{topicB})) {
    $similarity = $this->{_similarity}{$params->{topicA}}{$params->{topicB}};
    return $similarity if defined $similarity;
  }

  # get missing info
  if (defined $params->{topicA}) {
    $params->{tagsA} = $this->getTagsOfTopic($params->{topicA}) unless $params->{tagsA};
    $params->{catsA} = $this->getCategoriesOfTopic($params->{topicA}) unless $params->{catsA};
  }

  if (defined $params->{topicB}) {
    $params->{tagsB} = $this->getTagsOfTopic($params->{topicB}) unless $params->{tagsB};
    $params->{catsB} = $this->getCategoriesOfTopic($params->{topicB}) unless $params->{catsB};
  }

  # compute
  my (%tagsA, %tagsB, %catsA, %catsB);

  %tagsA = map {$_ => 1} @{$params->{tagsA}} if defined $params->{tagsA};
  %tagsB = map {$_ => 1} @{$params->{tagsB}} if defined $params->{tagsB};
  %catsA = map {$_ => 1} @{$params->{catsA}} if defined $params->{catsA};
  %catsB = map {$_ => 1} @{$params->{catsB}} if defined $params->{catsB};

  my $onlyA = 0;
  my $onlyB = 0;
  my $intersection = 0;

  if (defined $params->{tagsA} && defined $params->{tagsB}) {
    map {defined($tagsB{$_})?$intersection++:$onlyA++} @{$params->{tagsA}};
    map {$onlyB++ unless defined $tagsA{$_}} @{$params->{tagsB}};
  }
  if (defined $params->{catsA} && defined $params->{catsB}) {
    map {defined($catsB{$_})?$intersection+=CATWEIGHT:$onlyA+=CATWEIGHT} @{$params->{catsA}};
    map {$onlyB+=CATWEIGHT unless defined $catsA{$_}} @{$params->{catsB}};
  }

  my $total = $onlyA + $onlyB + $intersection;
  $similarity = $total?$intersection/$total:0;
  #if (TRACE && $similarity) {
  #  writeDebug("similarity($param->{topicA}, $params->{topicB}) = $similarity");
  #  writeDebug("onlyA=$onlyA, onlyB=$onlyB, intersection=$intersection, total=$total");
  #}

  # cache
  if (defined($params->{topicA}) && defined($params->{topicB})) {
    $this->{_similarity}{$params->{topicA}}{$params->{topicB}} = $similarity;
    $this->{gotUpdate} = 1;
  }

  return $similarity;
}

################################################################################
# return true if cat1 subsumes cat2 (is an ancestor of)
sub subsumes {
  my ($this, $cat1, $cat2) = @_;

  my $result = $this->catDistance($cat1, $cat2);
  return (defined($result) && $result >= 0)?1:0;
}

################################################################################
sub getTagsOfTopic {
  my ($this, $topic) = @_;

  #writeDebug("called getTagsOfTopic");
  # allow topicName or topicObj
  my $topicObj;
  if (ref($topic)) {
    $topicObj = $topic;
  } else {
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
    return undef unless $db;
    $topicObj = $db->fastget($topic);
  }
  return undef unless $topicObj;

  my $form = $topicObj->fastget("form");
  return undef unless $form;
  $form = $topicObj->fastget($form);
  return undef unless $form;

  # SMELL: do we need to filter for TaggedTopic?

  my $tags = $form->fastget('Tag');
  return undef unless $tags;

  $tags =~ s/^\s+|\s+$//g;
  my @tags = split(/\s*,\s*/, $tags);
  return \@tags;
}

################################################################################
sub getTags {
  my ($this) = @_;

  #writeDebug("called getTags");
  # allow topicName or topicObj
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  return undef unless $db;

  my %tags = ();
  foreach my $topic ($db->getKeys()) {
    my $topicObj = $db->fastget($topic);

    my $form = $topicObj->fastget("form");
    next unless $form;

    $form = $topicObj->fastget($form);
    next unless $form;

    # SMELL: do we need to filter for TaggedTopic?

    my $tags = $form->fastget('Tag');
    next unless $tags;

    $tags =~ s/^\s+|\s+$//g;
    $tags{$_} = 1 foreach split(/\s*,\s*/, $tags);
  }

  my @tags = sort keys %tags;

  return \@tags;
}

################################################################################
sub getCategoriesOfTopic {
  my ($this, $topic) = @_;

  # allow topicName or topicObj
  my $topicObj;
  if (ref($topic)) {
    $topicObj = $topic;
    $topic = $topicObj->fastget('topic');
  } else {
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
    return undef unless $db;
    $topicObj = $db->fastget($topic);
  }
  return undef unless $topicObj;

  my $cats = $this->{_catsOfTopic}{$topic};
  return $cats if defined $cats;

  my $form = $topicObj->fastget("form");
  return undef unless $form;
  $form = $topicObj->fastget($form);
  return undef unless $form;

  #writeDebug("getCategoriesOfTopic()"); 

  # get typed topics
  my $topicType = $form->fastget("TopicType");
  return undef unless $topicType;

  my $catFields = $this->getCatFields(split(/\s*,\s*/,$topicType));
  return undef unless $catFields;
  #writeDebug("catFields=".join(', ', @$catFields));

  # get all categories in all category formfields
  my %cats = ();
  foreach my $catField (@$catFields) {
    # get category formfield
    #writeDebug("looking up '$catField'");
    my $cats = $form->fastget($catField);
    next unless $cats;
    #writeDebug("$catField=$cats");
    foreach my $cat (split(/\s*,\s*/, $cats)) {
      $cat =~ s/^\s+|\s+$//g;
      $cats{$cat} = 1 if $cat && $cat ne 'TopCategory';
    }
  }
  @$cats = keys %cats;
  $this->{_catsOfTopic}{$topic} = $cats;
  $this->{gotUpdate} = 1;
  return $cats;
}


################################################################################
# get names of category formfields of a topictype
sub getCatFields {
  my ($this, @topicTypes) = @_;

  #writeDebug("called getCatFields()"); 
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  return () unless defined $db;

  my %allCatFields;
  foreach my $topicType (@topicTypes) {
    # lookup cache
    #writeDebug("looking up '$topicType' in cache");
    my $catFields = $this->{_catFields}{$topicType};
    if (defined($catFields)) {
      foreach my $cat (@$catFields) {
        $allCatFields{$cat} = 1;
      }
      next;
    }
    #writeDebug("looking up form definition for $topicType in web $this->{web}");
    @$catFields = ();
    $this->{_catFields}{$topicType} = $catFields;
    $this->{gotUpdate} = 1;

    # looup form definition -> ASSUMPTION: TopicTypes must be DataForms too
    my $formDef = $db->fastget($topicType);
    next unless $formDef;

    # check if this is a TopicStub
    my $formName = $formDef->fastget('form');
    next unless $formName; # woops got no form
    my $form = $formDef->fastget($formName);
    next unless $form;

    my $type = $form->fastget('TopicType') || '';
    #writeDebug("type=$type");

    if ($type =~ /\bTopicStub\b/ || $formName =~ /\bTopicStub\b/) {
      #writeDebug("reading stub");
      # this is a TopicStub, lookup the target
      my ($targetWeb, $targetTopic) = 
        Foswiki::Func::normalizeWebTopicName($this->{web}, $form->fastget('Target'));

      my $thisDB = Foswiki::Plugins::DBCachePlugin::getDB($targetWeb);
      next unless $thisDB;
      $formDef = $thisDB->fastget($targetTopic);
      next unless $formDef;# never reach
    }

    my $text = $formDef->fastget('text');
    my $inBlock = 0;
    $text =~ s/\r//g;
    $text =~ s/\\\n//g; # remove trailing '\' and join continuation lines
    # | *Name:* | *Type:* | *Size:* | *Value:*  | *Description:* | *Attributes:* |
    # Description and attributes are optional
    foreach my $line ( split( /\n/, $text ) ) {
      if ($line =~ /^\s*\|.*Name[^|]*\|.*Type[^|]*\|.*Size[^|]*\|/) {
        $inBlock = 1;
        next;
      }
      if ($inBlock && $line =~ s/^\s*\|\s*//) {
        $line =~ s/\\\|/\007/g; # protect \| from split
        my ($title, $type, $size, $vals) =
          map { s/\007/|/g; $_ } split( /\s*\|\s*/, $line );
        $type ||= '';
        $type = lc $type;
        $type =~ s/^\s+|\s+$//g;
        next if !$title or $type ne 'cat';
        $title =~ s/<nop>//g;
        push @$catFields, $title;
      } else {
        $inBlock = 0;
      }
    }

    # cache
    #writeDebug("setting cache for '$topicType' to ".join(',',@$catFields));
    $this->{_catFields}{$topicType} = $catFields;
    foreach my $cat (@$catFields) {
      $allCatFields{$cat} = 1;
    }
  }
  my @allCatFields = sort keys %allCatFields;

  #writeDebug("... result=".join(",",@allCatFields));

  return \@allCatFields;
}

###############################################################################
sub getCategories {
  my $this = shift;

  unless (defined($this->{_categories})) {
    $this->init();
    confess "no categories for $this->{web}" unless defined $this->{_categories};
  }
  return values %{$this->{_categories}}
}

###############################################################################
sub getCategoryNames {
  my $this = shift;

  unless (defined($this->{_categories})) {
    $this->init();
    confess "no categories for $this->{web}" unless defined $this->{_categories};
  }
  return keys %{$this->{_categories}}
}


###############################################################################
sub getCategory {
  my ($this, $name) = @_;

  return undef unless $name;

  unless (defined($this->{_categories})) {
    $this->init();
    confess "no categories for $this->{web}" unless defined $this->{_categories};
  }
  my $cat = $this->{_categories}{$name};

  unless ($cat) {
    # try id
    if ($name =~ /^\d+/) {
      foreach my $cat (values %{$this->{_categories}}) {
        last if $cat->{id} eq $name;
      }
    }
  }

  if ($cat) {
    my $cache = $Foswiki::Plugins::SESSION->{cache};
    if (defined $cache) {
      #print STDERR "### addDependency($cat->{origWeb}, $cat->{name})\n";
      $cache->addDependency($cat->{origWeb}, $cat->{name})
        if $cat->{origWeb}; # if it has got a physical topic
    }
  }

  return $cat
}

###############################################################################
sub setCategory {
  $_[0]->{_categories}{$_[1]} = $_[2];
}

###############################################################################
sub createCategory {
  return new Foswiki::Plugins::ClassificationPlugin::Category(@_);
}

###############################################################################
# static
sub inlineError {
  return '<span class="foswikiAlert">' . $_[0] . '</span>' ;
}

###############################################################################
sub traverse {
  my ($this, $params) = @_;

  writeDebug("called traverse for hierarchy in '$this->{web}'");

  my $top = $params->{top} || 'TopCategory';
  my $sort = $params->{sort} || '';

  my @result;
  my $nrCalls = 0;
  my $seen = {};

  my @cats = map { $this->getCategory($_) } split(/\s*,\s*/,$top);
  $this->sortCategories(\@cats, $sort);

  my $nrSiblings = scalar(@cats);
  my $user = Foswiki::Func::getWikiName();
  foreach my $cat (@cats) {
    if ($cat && Foswiki::Func::checkAccessPermission("view", $user, undef, $cat->{name}, $this->{web})) {
      my $catResult =  $cat->traverse($params, \$nrCalls, 1, $nrSiblings, $seen);
      push @result, $catResult if $catResult;
    }
  }

  my $result = '';
  my $count = scalar($this->getCategories) - 2;

  if (@result) {
    my $separator = $params->{separator} || '';
    my $header = $params->{header} || '';
    my $footer = $params->{footer} || '';

    $separator = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($separator);
    $result = join($separator, @result);

    $header = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($header,
      depth=>0,
      indent=>'',
      count=>$count,
    );
    $footer = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($footer,
      depth=>0,
      indent=>'',
      count=>$count,
    );
    $result = $header.$result.$footer;
  } else {
    my $nullFormat = $params->{nullformat} || '';

    $result = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($nullFormat,
      depth=>0,
      indent=>'',
      count=>$count,
    );
  }

  writeDebug("done traverse");

  return $result;
}

###############################################################################
# get preferences of a set of categories
sub getPreferences {
  my ($this, @cats) = @_;

  unless ($this->{_prefs}) {
    my $session = $Foswiki::Plugins::SESSION;

    require Foswiki::Prefs;
    my $prefs = new Foswiki::Prefs($session);

    require Foswiki::Prefs::PrefsCache;
    $prefs = new Foswiki::Prefs::PrefsCache($prefs, undef, 'CAT'); 

    foreach my $cat (@cats) {
      $cat =~ s/^\s+|\s+$//g;
      my $catObj = $this->getCategory($cat);
      $prefs = $catObj->getPreferences($prefs);
    }

    $this->{_prefs} = $prefs;
  }

  return $this->{_prefs};
}


###############################################################################
sub checkAccessPermission {
  my ($this, $mode, $user, $topic, $order) = @_;

  # get acl attribute
  my $aclAttribute = $this->{_aclAttribute};

  unless (defined $aclAttribute) {
    $aclAttribute = 
      Foswiki::Func::getPreferencesValue('CLASSIFICATIONPLUGIN_ACLATTRIBUTE', $this->{web}) || 
      'Category';
    $this->{_aclAttribute} = $aclAttribute;
  }

  # get categories and gather access control lists
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});
  return undef unless $db;
  my $topicObj = $db->fastget($topic);
  return undef unless $topicObj;

  my $form = $topicObj->fastget('form');
  return undef unless $form;

  $form = $topicObj->fastget($form);
  return undef unless $form;

  my $cats = $form->fastget($aclAttribute);
  return undef unless $cats;

  #my $prefs = $this->getPreferences(split(/\s*,\s*/, $cats));

  my $allowed = 1;

  return $allowed;
}

###############################################################################
sub collectTopicsOfCategory {
  my ($this) = @_;

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{web});

  writeDebug("collecting topics in $this->{web}");

  # reset _topics
  foreach my $cat ($this->getCategories()) {
    $cat->{_topics} = {};
    $cat->{gotUpdate} = 1;
  }
  $this->{_top}{_topics} = {};

  foreach my $topicName ($db->getKeys()) {
    my $topicObj = $db->fastget($topicName);
    next unless $topicObj;

    my $form = $topicObj->fastget("form");
    next unless $form;

    $form = $topicObj->fastget($form);
    next unless $form;

    my $topicTypes = $form->fastget('TopicType');
    next unless $topicTypes;

    next if $topicTypes =~ /\bCategory\b/o;

    my $cats = $this->getCategoriesOfTopic($topicObj);
    push @$cats, 'TopCategory' if !$cats || !@$cats;

    foreach my $catName (@$cats) {
      my $cat = $this->getCategory($catName);
      writeDebug("adding $topicName it to category $catName");
      $cat->{_topics}{$topicName} = 1;
    }
  }

  $this->{gotUpdate} = 1;
}

###############################################################################
sub filterCategories {
  my ($this, $params) = @_;

  my $title = $params->{title};
  my $name = $params->{name};
  my $callback = $params->{callback};
  my $caseSensitive = Foswiki::Func::isTrue($params->{casesensitive}, 0);

  my @result = ();
  foreach my $cat (values %{$this->{_categories}}) {
    if ($caseSensitive) {
      next if defined $title && $cat->title !~ /$title/;
      next if defined $name && $cat->{name} !~ /$name/;
    } else {
      next if defined $title && $cat->title !~ /$title/i;
      next if defined $name && $cat->{name} !~ /$name/i;
    }
    if (defined $callback) {
      &$callback($cat);
    } else {
      push @result, $cat;
    }
  }

  return @result;
}

###############################################################################
sub sortCategories {
  my ($this, $cats, $crit) = @_;

  return unless $cats && @$cats;

  if ($crit eq 'order') {
    @$cats = sort { $a->order <=> $b->order } @$cats;

    return $cats;
  }

  if ($crit =~ /^(name|title)$/) {
    @$cats = sort { $a->{$crit} cmp $b->{$crit} } @$cats;

    return $cats;
  }

  @$cats =
    sort { 
      $a->order <=> $b->order || 
      $a->title cmp $b->title 
    } @$cats;

  return $cats;
}

###############################################################################
sub translate {
  my ($this, $text) = @_;

  return "" unless defined $text && $text ne "";

  unless (defined $this->{_translate}{"$text"}) {
    if (Foswiki::Func::getContext()->{MultiLingualPluginEnabled}) {
      require Foswiki::Plugins::MultiLingualPlugin;
      $text = Foswiki::Plugins::MultiLingualPlugin::translate($text, $this->{hierarchy}{web});
    } else {
      my $session = $Foswiki::Plugins::SESSION;
      $text = $session->i18n->maketext($text);
    }
    $this->{_translate}{"$text"} = $text;
  }

  return $this->{_translate}{"$text"};
}



1;
