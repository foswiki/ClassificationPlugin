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

package Foswiki::Plugins::ClassificationPlugin::Category;

use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::Search ();
use Foswiki::Plugins::DBCachePlugin ();
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();

use constant TRACE => 0; # toggle me

###############################################################################
# static
sub writeDebug {
  print STDERR ' - ClassificationPlugin::Category - '.$_[0]."\n" if TRACE;
}

################################################################################
# constructor
sub new {
  my $class = shift;
  my $hierarchy = shift;
  my $name = shift;

  my $this = {
    name=>$name,
    origWeb=>$hierarchy->{web},
    id=>$hierarchy->{idCounter}++,
    hierarchy=>$hierarchy,
    summary=>'',
    title=>$name,
    order=>99999999,
    @_
  };
  $this->{gotUpdate} = 1;

  $this = bless($this, $class);

  # register to hierarchy
  $hierarchy->setCategory($name, $this);

  #writeDebug("new category name=$this->{name} title=$this->title web=$hierarchy->{web}"); 

  return $this;
}

###############################################################################
sub title {
  my ($this, $val) = @_;

  if (defined $val) {
    $val = urlDecode($val);
    if ($val ne ($this->{title}//'')) {
      $this->{title} = $val;
      $this->{gotUpdate} = 1;
    }
  } 

  return $this->{hierarchy}->translate($this->{title});
}

###############################################################################
sub summary {
  my ($this, $val) = @_;

  if (defined $val) {
    $val = urlDecode($val);
    if ($val ne ($this->{summary}//'')) {
      $this->{summary} = $val;
      $this->{gotUpdate} = 1;
    }
  }

  return $this->{hierarchy}->translate($this->{summary});
}

###############################################################################
sub redirect {
  my ($this, $val) = @_;

  if (defined $val) {
    if ($val ne ($this->{redirect}//'')) {
      $this->{redirect} = $val;
      $this->{gotUpdate} = 1;
    }
  }

  return $this->{redirect};
}

###############################################################################
sub icon {
  my ($this, $val) = @_;

  if (defined $val && $val ne ($this->{icon}//'')) {
    $this->{icon} = $val;
    $this->{gotUpdate} = 1;
  }

  return $this->{icon};
}

###############################################################################
sub getIcon {
  my $this = shift;

  my $icon = $this->icon || 'folder';
  
  # remove file extension for backwards compatibility
  $icon =~ s/\.(png|gif)$//;

  return Foswiki::Plugins::JQueryPlugin::handleJQueryIcon($Foswiki::Plugins::SESSION, {
    _DEFAULT => $icon
  });
}

###############################################################################
sub getIconUrl {
  my $this = shift;

  my $icon = $this->icon || 'folder';

  # remove file extension for backwards compatibility
  $icon =~ s/\.(png|gif)$//;

  return Foswiki::Plugins::JQueryPlugin::Plugins::getIconUrlPath($icon);
}

###############################################################################
sub order {
  my ($this, $val, $meta) = @_;

  if (defined $val && ($this->{order} ne $val || defined $meta)) {

    $this->{order} = $val;
    $this->{gotUpdate} = 1;

    if (defined $meta) {
      my $field = $meta->get('FIELD', 'Order');
      unless ($field) {
        $field = {
          name => "Order",
          title => "Order", 
          attributes => "",
        };
      }
      $field->{value} = $val;
      $meta->putKeyed('FIELD', $field);
    }
  }

  return $this->{order};
}


###############################################################################
sub purgeCache {
  my $this = shift;

  writeDebug("purging category cache for $this->{name}");
  undef $this->{_topics};
  undef $this->{_tags};
  undef $this->{_prefs};
  undef $this->{_subsumes};
  undef $this->{_contains};
  undef $this->{_nrLeafs};
  undef $this->{_isCyclic};
  undef $this->{_perms};

  $this->{gotUpdate} = 1;
}

###############################################################################
# destructor
sub DESTROY {
  my $this = shift;

  undef $this->{icon};
  undef $this->{parents};
  undef $this->{allparents};
  undef $this->{children};
  undef $this->{hierarchy};
}

###############################################################################
sub init {
  my $this = shift;

  my $key = $this->{hierarchy}{web};
  $key .= '.'.$this->{hierarchy}{topic} if defined $this->{hierarchy}{topic};

  writeDebug("init category $this->{name} in $key");
  foreach my $name (keys %{$this->{parents}}) {
    my $parent = $this->{parents}{$name};

    # make sure the parents are pointers, not the category names
    unless (ref($parent)) {
      $parent = $this->{hierarchy}->getCategory($name);
      if ($parent) {
        $this->{parents}{$name} = $parent;
      } else {
        writeDebug("parent $name of $this->{name} NOT found in $key");
        delete $this->{parents}{$name};
      }
    }

    # establish child relation
    $parent->addChild($this) if $parent;
  }

  $this->{gotUpdate} = 1;
}

###############################################################################
sub getLeafs {
  my ($this, $result, $seen) = @_;

  $seen ||= {};
  $result ||= {};

  return keys %$result if $seen->{$this};
  $seen->{$this} = 1;

#  foreach my $topic ($this->getTopics()) {
#    $result->{$topic} = 1;
#  }

  my $foundChild = 0;
  foreach my $child ($this->getChildren()) {
    next if $child->{name} eq 'BottomCategory';
    $foundChild = 1;
    $child->getLeafs($result, $seen);
  }
  
  unless($foundChild) {
    $result->{$this->{name}} = 1;
    #writeDebug("found leaf $this->{name}");
  }

  return keys %$result;
}

###############################################################################
sub countLeafs {
  my ($this, $filter) = @_;
	
  $filter ||= '';
  my $nrLeafs = $this->{_nrLeafs}{$filter};

  unless (defined $nrLeafs) {
    #writeDebug("counting leafs of $this->{name}, filter=$filter");

    my @leafs = $this->getLeafs();
    if ($filter) {
      my $db = Foswiki::Plugins::DBCachePlugin::getDB($this->{hierarchy}{web});
      my $search= new Foswiki::Contrib::DBCacheContrib::Search($filter);
      $nrLeafs = 0;
      foreach my $topicName (@leafs) {
        my $topicObj = $db->fastget($topicName);
        next if $search->matches($topicObj);
        $nrLeafs++;
      }
    } else {
      $nrLeafs = scalar(@leafs);
    }
    $nrLeafs--;
    $nrLeafs = 0 unless $nrLeafs > 0;

    $this->{_nrLeafs}{$filter} = $nrLeafs;
    $this->{gotUpdate} = 1;
    #writeDebug("countLeafs($this->{name})=$nrLeafs");
  }

  return $nrLeafs;
}

###############################################################################
# recursive version of the Wallace-Kollias for transitive closure
sub computeDistance {
  my ($this, $distance, $ancestors) = @_;

  my $thisId = $this->{id};
  return if $ancestors->{$thisId};

  # become an ancestor
  $ancestors->{$thisId} = $this;
  $$distance[$thisId][$thisId] = 0;
      
  # loop over all ancestors
  foreach my $ancestor (values %$ancestors) {
    next unless $ancestor;
    my $ancestorId = $ancestor->{id};
    my $newDistance = $$distance[$ancestorId][$thisId] + 1;

    # loop over all children
    foreach my $child ($this->getChildren()) {
      my $childId = $child->{id};
      my $ancestorToChild = $$distance[$ancestorId][$childId];

      # ... to find out if there is a shorter path
      if (!$ancestorToChild || $newDistance < $ancestorToChild) {
        $$distance[$ancestorId][$childId] = $newDistance;
        #writeDebug("computed distance ($ancestor->{name},$child->{name})=$newDistance");
      }
    }
  }

  # recursion
  foreach my $child ($this->getChildren()) {
    $child->computeDistance($distance, $ancestors);
  }

  $ancestors->{$thisId} = 0;
}

###############################################################################
sub distance {
  my ($this, $that) = @_;

  return $this->{hierarchy}->catDistance($this, $that);
}

###############################################################################
sub subsumes {
  my ($this, $that) = @_;

  return $this->{hierarchy}->subsumes($this, $that);
}

###############################################################################
# returns 1 if the given topic is in the current category or any sub-category
sub contains {
  my ($this, $topic) = @_;

  return 1 if $this->{name} eq 'TopCategory';
  return 0 if $this->{name} eq 'BottomCategory';

  my $result = $this->{_contains}{$topic};
  return $result if defined $result;

  $result = 0;
  my $hierarchy = $this->{hierarchy};
  my $cat = $hierarchy->getCategory($topic);
  return 0 if $cat;  
  my $cats = $hierarchy->getCategoriesOfTopic($topic);
  if ($cats) {
    foreach my $cat (@$cats) {
      #writeDebug("checking $cat");
      $result = $hierarchy->subsumes($this, $cat);
      last if $result;
    }
  }
  #writeDebug("called contains($this->{name}, $topic) = $result");
  
  # cache
  $this->{_contains}{$topic} = $result;
  $this->{gotUpdate} = 1;
  return $result;
}

###############################################################################
sub setParents {
  my $this = shift;

  #writeDebug("called $this->{name}->setParents(@_)");
  foreach my $parent (@_) {
    my $parentObj = $parent;
    my $parentName = $parent;
    if(ref($parentObj)) {
      $parentName = $parentObj->{name};
    } else {
      $parentObj = $this->{hierarchy}->getCategory($parent) || 1;
    }
    #die "can't set myself as a parent" if $this eq $parentObj;
    $this->{parents}{$parentName} = $parentObj;
  }
  $this->{gotUpdate} = 1;
}

###############################################################################
sub reparent {
  my ($this, $newParent, $oldParent, $meta) = @_;

  return $meta if defined($oldParent) && $newParent eq $oldParent; # nop

  my $doSave = 0;

  unless ($meta) {
    ($meta) = Foswiki::Func::readTopic($this->{origWeb}, $this->{name});
    $doSave = 1;    # save if we read the topic ourselves
  }

  my $field = $meta->get('FIELD', 'Category');
  unless ($field) {
    $field = {
      name => 'Category',
      title => 'Category',
      attributes => '',
      value => '',
    };
  }

  my %cats = map { $_ => 1 } split(/\s*,\s*/, $field->{value});

  if (defined $oldParent) {
    # remove it from one old parent
    delete $cats{$oldParent->{name}};
    $oldParent->removeChild($this);
  } else {
    # remove it from all old parents
    foreach my $parent ($this->getParents) {
      $parent->removeChild($this);
    }
    %cats = ();
  }
  $cats{$newParent->{name}} = 1;
  $this->setParents($newParent);

  $field->{value} = join(", ", sort keys %cats);
  $meta->putKeyed('FIELD', $field);

  Foswiki::Func::saveTopic($this->{origWeb}, $this->{name}, $meta) if $doSave;

  return $meta;
}

###############################################################################
# get all parent nodes
# subdsumes may be a category or category name to restrict parents to those
# being subsumed
sub getParents {
  my ($this, $subsumes) = @_;

  my $subsumesCat;
  if ($subsumes) {
    if (ref($subsumes)) { 
      $subsumesCat = $subsumes;
    } else {
      $subsumesCat = $this->{hierarchy}->getCategory($subsumes);
    }
  }

  return values %{$this->{parents}} unless $subsumesCat;

  my @parents = ();
  foreach my $parent (values %{$this->{parents}}) {
    push @parents, $parent if $subsumesCat->subsumes($parent);
  }

  return @parents;
}

###############################################################################
# get the "natural" parent
sub getParent {
  my ($this, $subsumes) = @_;

  my @parents = sort {uc($a->title) cmp uc($b->title)} $this->getParents($subsumes);

  return unless @parents;
  return shift @parents;
}


###############################################################################
sub getAllParents {
  my $this = shift;

  return keys %{$this->_getAllParents()};
}

###############################################################################
sub _getAllParents {
  my ($this, $seen) = @_;

  return {} if $this eq $this->{hierarchy}{_top};
  $seen ||= {};

  if (!defined ($this->{allparents}) && !$seen->{$this->{name}}) {

    $seen->{$this->{name}} = 1;
    $this->{allparents} = {};
    
    my @parents = $this->getParents();
    foreach my $parent (@parents) {
      $this->{allparents}{$parent->{name}} = 1 unless $parent eq $this->{hierarchy}{_top};
      $this->{allparents} = {%{$this->{allparents}}, %{$parent->_getAllParents($parent, $seen)}};
    }
    $this->{gotUpate} = 1;
  }

  return $this->{allparents};
}

###############################################################################
sub countTopics {
  my ($this, $filter) = @_;

  my @topics = $this->getAllTopics();

  @topics = $this->filterTopics(\@topics, $filter) if $filter;

  return scalar(@topics);
}

###############################################################################
sub getAllTopics {
  my ($this, $seen) = @_;

  $seen ||= {};

  return () if $seen->{$this->{name}};
  $seen->{$this->{name}} = 1;

  my @topics = $this->getTopics;

  foreach my $child ($this->getChildren()) {
    next if $child->{name} eq 'BottomCategory';
    push @topics, $child->getAllTopics($seen);
  }

  my %topics = map {$_ => 1} @topics;
  return keys %topics;
}

###############################################################################
sub getTopics {
  my ($this, $filter) = @_;

  unless (defined($this->{_topics})) {
   # writeDebug("$this->{name} triggers collecting topics of categories in $this->{hierarchy}{web}");
    $this->{hierarchy}->collectTopicsOfCategory();
  } else {
    #writeDebug("_topics found in cache of $this->{name}");
  }

  my @topics = ();
  my $user = Foswiki::Func::getWikiName();
  if (Foswiki::Func::isAnAdmin($user)) {
    @topics = keys %{$this->{_topics}};
  } else {
    my $web = $this->{hierarchy}{web};
    foreach my $topic (keys %{$this->{_topics}}) {
      if (Foswiki::Func::checkAccessPermission("view", $user, undef, $topic, $web)) {
        push @topics, $topic;
      }
    }
  }

  return @topics unless $filter;
  return $this->filterTopics(\@topics, $filter);
}

###############################################################################
sub filterTopics {
  my ($this, $topics, $filter) = @_;

  return @$topics unless $filter && @$topics;

  my $hierarchy = $this->{hierarchy};
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($hierarchy->{web});
  my $search = new Foswiki::Contrib::DBCacheContrib::Search($filter);

  return grep {
    my $topicObj = $db->fastget($_);
    $topicObj && $search->matches($topicObj);
  } @$topics;
}

###############################################################################
sub getTagsOfTopics {
  my $this = shift;

  unless (defined($this->{_tags})) {
    #writeDebug("gathering tags in category $this->{name}");
    my %tags;
    my $hierarchy = $this->{hierarchy};
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($hierarchy->{web});
    foreach my $topic ($this->getTopics()) {
      my $topicObj = $db->fastget($topic);
      next unless $topicObj;
      my $form = $topicObj->fastget("form");
      next unless $form;
      $form = $topicObj->fastget($form);
      next unless $form;
      my $tags = $form->fastget('Tag');
      next unless $tags;
      foreach my $tag (split(/\s*,\s*/, $tags)) {
        $tags{$tag}++;
      }
    }
    %{$this->{_tags}} = %tags;
  }

  return keys %{$this->{_tags}};
}

###############################################################################
# register a subcategory
sub addChild {
  my ($this, $category) = @_;

 unless (defined $category->{name}) {
   my ($package, $file, $line) = caller;
   die "no name in category called from $package, line $line";
 }

  #writeDebug("called $this->{name}->addChild($category->{name})");
  $this->{children}{$category->{name}} = $category;
  $this->{gotUpdate} = 1;
}

###############################################################################
sub removeChild {
  my ($this, $child) = @_;

  if (delete $this->{children}{$child->{name}}) {
    $this->{gotUpdate} = 1;
  }
}

###############################################################################
sub getChildren {
  return values %{$_[0]->{children}};
}

###############################################################################
sub isCyclic {
  my $this = shift;

  my $result = $this->{_isCyclic};
  return $result if defined $result;

  #writeDebug("called isCyclic($this->{name})");

  $result = 0;
  foreach my $child ($this->getChildren()) {
    next if $child->{name} eq 'BottomCategory';
    $result = $child->subsumes($this);
    if ($result) {
      #writeDebug("child $child->{name} subsumes $this->{name}: $result");
      last;
    }
  }
  
  # cache
  $this->{_isCyclic} = $result;
  $this->{gotUpdate} = 1;
  return $result;
}

###############################################################################
sub checkAccessPermission {
  my ($this, $user, $type, $seen) = @_;

  return 1 if $this->{name} =~ /^(TopCategory|BottomCategory)$/;

  $type ||= 'VIEW';
  $seen ||= {};

  # prevent infinit recursions
  return 0 if $seen->{$this};
  $seen->{$this} = 1;

  # normalize calling parameter not to trash the cache
  $user = Foswiki::Func::getWikiName($user);

  # lookup cache
  my $access = $this->{_perms}{$type}{$user};

  unless (defined $access) {
    my $topic = $this->{name};
    my $web = $this->{origWeb};
    #writeDebug("checking $type access to category $web.$topic for $user");
    $access = Foswiki::Func::checkAccessPermission($type, $user, undef, $topic, $web);
  
    if ($access) {
      # recurse til access granted
      foreach my $parent (values %{$this->{parents}}) {
        next if $parent->{name} eq 'TopCategory';
        $access = $parent->checkAccessPermission($user, $type, $seen);
        last if $access;
      }
    }

    # cache result
    $this->{_perms}{$type}{$user} = $access;
  }

  return $access;
}

###############################################################################
sub getPreferences {
  my ($this) = @_;

  unless ($this->{_prefs}) {
    require Foswiki::Prefs::PrefsCache;
    $this->{_prefs} = new Foswiki::Prefs::PrefsCache($this->{hierarchy}{_prefs}, undef, 'CAT', 
      $this->{origWeb}, $this->{name}); 
  }
  
  return $this->{_prefs};
}

###############################################################################
sub importCategories {
  my ($this, $impCats) = @_;

  return unless $impCats;

  writeDebug("called importCategories($impCats)");

  my $thisHierarchy = $this->{hierarchy};
  my $thisWeb = $thisHierarchy->{web};
  foreach my $impCat (split(/\s*,\s*/, $impCats)) {

    my ($impWeb, $impTopic) = Foswiki::Func::normalizeWebTopicName($thisWeb, $impCat);
    $impWeb =~ s/\//\./go;
    next unless Foswiki::Func::webExists($impWeb);

    my $db = Foswiki::Plugins::DBCachePlugin::getDB($impWeb);
    my $impObj = $db->fastget($impTopic);
    next unless $impObj;

    my $form = $impObj->fastget("form");
    next unless $form;

    $form = $impObj->fastget($form);
    next unless $form;

    my $topicType = $form->fastget("TopicType");

    my $impHierarchy;

    # import a topic-based category tree

    # prevent deep recursion importing from the same web
    next if $thisWeb eq $impWeb;

    # SMELL: prevent deep recursion of two webs importing each other's categories
    $impHierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($impWeb);
    next unless $impHierarchy;

    $impCat = $impHierarchy->getCategory($impTopic);
    next unless $impCat;

    # import all children
    foreach my $impChild ($impCat->getChildren) {
      next if $impChild->{name} eq 'BottomCategory';
      my $clone = $impChild->import($thisHierarchy);
      $clone->{parents} = {$this->{name} => 1};
      $this->addChild($clone);
    }
  }

  $this->{gotUpdate} = 1;
}

###############################################################################
sub importCategoriesFromText {
  my ($this, $text, $targetHierarchy) = @_;

  die "no targert hierarchy" unless defined $targetHierarchy;

  my $prefix = $this->{name};
  $prefix =~ s/Category$//;
  
  writeDebug("called importCategoriesFromText()");
  my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchyFromText($text, 
    prefix => $prefix
  );
  my $top = $hierarchy->getCategory("TopCategory");

  # import all children
  foreach my $impChild ($top->getChildren) {
    next if $impChild->{name} eq 'BottomCategory';
    my $clone = $impChild->import($targetHierarchy);
    $clone->{parents} = {$this->{name} => 1};
    $this->addChild($clone);
  }
}

###############################################################################
sub import {
  my ($this, $hierarchy, $seen) = @_;

  $seen ||= {};
  return if $seen->{$this->{name}};
  $seen->{$this->{name}} = 1;

  my $cat = $hierarchy->createCategory($this->{name});
  $cat->title($this->title);
  $cat->summary($this->summary);
  $cat->order($this->order);
  $cat->icon($this->icon);
  $cat->redirect($this->redirect);
  $cat->{origWeb} = $hierarchy->{web};

  # import all children
  foreach my $child ($this->getChildren()) {
    next if $child->{name} eq 'BottomCategory';
    my $clone = $child->import($hierarchy, $seen);
    next unless $clone;
    $clone->{parents} = {$cat->{name} => 1};
    $cat->addChild($clone);
  } 

  return $cat;
}

###############################################################################
sub getBreadCrumbs {
  my ($this, $subsumes) = @_;

  my @breadCrumbs = ();
  my %seen = ();

  my $parent = $this;

  while ($parent) {
    last if $seen{$parent->{name}};
    $seen{$parent->{name}} = 1;

    push @breadCrumbs, $parent;

    $parent = $parent->getParent($subsumes);
    last if !$parent || $parent eq $parent->{hierarchy}{_top};
  }


  return reverse @breadCrumbs;
}

###############################################################################
sub getAllBreadCrumbs {
  my ($this, $separator, $seen) = @_;

  $seen ||= {};
  return () if $seen->{$this->{name}};
  $seen->{$this->{name}} = 1;

  $separator = "." unless defined $separator;

  my @parents = $this->getParents();

  my @result = ();
  foreach my $parent (@parents) {
    next if $parent->{name} eq 'TopCategory';
    foreach my $item ($parent->getAllBreadCrumbs($separator, $seen)) {
      push @result, $item.$separator.$this->{name};
    }
  }

  return ($this->{name}) unless @result;

  return @result;
}

###############################################################################
sub getLink {
  my ($this, $doRedirect) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  my $request = Foswiki::Func::getRequestObject();

  my $baseWeb = $session->{webName};
  my $baseTopic = $request->param("catname") || $session->{topicName};

  my $currentTopic = '';
  $currentTopic = ' foswikiCurrentTopicLink' 
    if ($baseWeb eq $this->{hierarchy}{web} && $baseTopic eq $this->{name}) || $request->param("catname");

  my $class = $currentTopic?" class='$currentTopic'":"";
  return "<a href='".$this->getUrl($doRedirect)."'$class><noautolink>".$this->title."</noautolink></a>";
}

###############################################################################
sub getUrl {
  my ($this, $doRedirect) = @_;
  
  my $hierWeb = $this->{hierarchy}{web};

  $doRedirect = 1 unless defined $doRedirect;

  if ($doRedirect && $this->redirect) {
    return Foswiki::Func::getScriptUrlPath($hierWeb, $this->redirect, 'view');
  } 

  my $url;
  if (Foswiki::Func::topicExists($hierWeb, $this->{name})) {
    $url = Foswiki::Func::getScriptUrlPath($hierWeb, $this->{name}, 'view');
  } else {
    $url = Foswiki::Func::getScriptUrlPath($hierWeb, 'TopCategory', 'view', catname=>$this->{name});
  }

  return $url;
}

###############################################################################
# get a list of all offsprings
sub getSubCategories {
  my ($this, $minDepth, $maxDepth) = @_;

  my %result = ();
  $minDepth ||= 1;
  $maxDepth ||= 99999999;
  $this->_getSubCategories($minDepth, $maxDepth, \%result);
  return values %result;
}

sub _getSubCategories {
  my ($this, $minDepth, $maxDepth, $result) = @_;

  return if $maxDepth <= 0;

  my $botCat = $this->{hierarchy}{_bottom};
  foreach my $child ($this->getChildren()) {
    next if $child eq $botCat;
    next if $result->{$child->{name}};

    $result->{$child->{name}} = $child if $minDepth <= 1;
    $child->_getSubCategories($minDepth-1, $maxDepth-1, $result);
  }
}


###############################################################################
sub traverse {
  my ($this, $params, $nrCalls, $index, $nrSiblings, $seen, $depth, $parentTitle) = @_;

  $depth ||= 0;

  my $maxDepth = $params->{depth};
  return '' if defined($maxDepth) && $depth >= $maxDepth;

  $index ||= 1;
  $nrSiblings ||= 1;
  $seen ||= {};
  return '' if $seen->{$this};
  $seen->{$this} = 1;

  #return '' unless $this->checkAccessPermission();
  $$nrCalls++;

  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';
  my $format = $params->{format};
  my $separator = $params->{separator} || '';
  my $sort = $params->{sort} || '';

  # use topformat if we render the top category and there's only one sibling
  if ($nrSiblings == 1) {
    $format = $params->{topformat} if defined $params->{topformat};
  }

  my $matchAttr = $params->{matchattr} || 'name';
  $matchAttr = 'name' unless $matchAttr =~ /^(name|title)$/;
  my $matchCase = $params->{matchcase} || 'on';

  $format = '<ul><li><img src="$icon" /> <a href="$url">$title</a> $children</li></ul>' 
    unless defined $format;

  # get sub-categories
  my @children = map {
    $this->{children}{$_}
  } grep {!/^BottomCategory$/} keys %{$this->{children}};

  $this->{hierarchy}->sortCategories(\@children, $sort);
  my $nrChildren = scalar(@children);

  #writeDebug("traverse() nrCalls=$$nrCalls, depth=$depth, name=$this->{name} order=".$this->order);
  #writeDebug("children=".join(', ', map {$_->{name}} @children));

  my $doChildren = (@children)?1:0;
  my $isExpanded = 0; # set to true if this category is opened by a subsumed opener
  my $isOpener = 0;
  if ($params->{open}) {
    $doChildren = 0;
    my %openers = ();
    if (defined $params->{_openers}) {
      %openers = %{$params->{_openers}};
    } else {
      my $openers = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($params->{open},
        'web'=>$this->{hierarchy}{web}, 
        'origweb'=>$this->{origWeb} || '', 
        'topic'=>$this->{name},
        'name'=>$this->{name},
        'summary'=>$this->summary,
        'title'=>$this->title,
        'order'=>$this->order,
      );
      $openers = Foswiki::Func::expandCommonVariables($openers);
      my $isCacheable = ($params->{open} eq $openers)?1:0;
      $openers =~ s/^\s*(.*?)\s*$/$1/;
      #writeDebug("openers=$openers");
      %openers = map {$_ => 1} split(/\s*,\s*/, $openers);
      $params->{_openers} = \%openers if $isCacheable;
    }
    $isOpener = ($openers{$this->{name}})?1:0;
    foreach my $opener (keys %openers) {
      #writeDebug("checking at $this->{name} opener '$opener'");
      my $distance = $this->distance($opener);
      #if ($this->subsumes($opener)) {
      # open thos that show up within the given depth
      if (defined $distance && $distance >= 0 && (!$maxDepth || $distance <= $maxDepth)) {
        #writeDebug("$this->{name} opened by $opener");
        $doChildren = 1;
        $isExpanded = 1;
        last;
      }
    }
  }

  #print STDERR "$this->{name}: isOpener=$isOpener, isExpanded=$isExpanded, doChildren=$doChildren\n";

  if (!$isOpener && !$isExpanded && $params->{hideclosed} && $params->{hideclosed} eq 'on') {
    #writeDebug("hideclosed $this->{name} / ".$this->title);
    return '';
  }


  my @subResult;
  my $childIndex = 1;
  if ($doChildren) {
    #writeDebug("doing children of $this->{name}/".$this->title");
    my $user = Foswiki::Func::getWikiName();
    my $web = $this->{hierarchy}{web};
    foreach my $child (@children) {
      next if $child->{name} eq 'BottomCategory';
      next unless Foswiki::Func::checkAccessPermission("view", $user, undef, $child->{name}, $web);
      my $childResult = $child->traverse($params, $nrCalls, $childIndex, $nrChildren, $seen, $isExpanded?$depth:$depth+1, $this->title);
      push @subResult, $childResult if $childResult;
      $childIndex++;
    }
  } else {
    #writeDebug("not decending at $this->{name}");
    if (@children) {
      my $placeholder = $params->{placeholder};
      push @subResult, $placeholder if $placeholder;
    }
  }

  my $subResult = '';
  if (@subResult) {
    $separator = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($separator);
    $subResult = join($separator, @subResult);
  }

  my $unique = $params->{unique} || 'off';
  $seen->{$this} = 0 unless $unique eq 'on';

  my $minDepth = $params->{mindepth};

  return $subResult 
    if $minDepth && $depth <= $minDepth;

  if ($matchCase eq 'on') {
    return $subResult
      if defined $params->{exclude} && $this->{$matchAttr} =~ /^($params->{exclude})$/;
    return $subResult
      if defined $params->{include} && $this->{$matchAttr} !~ /^($params->{include})$/;
  } else {
    return $subResult
      if defined $params->{exclude} && $this->{$matchAttr} =~ /^($params->{exclude})$/i;
    return $subResult
      if defined $params->{include} && $this->{$matchAttr} !~ /^($params->{include})$/i;
  }

  my $filter = $params->{filter};
  my $nrTopics;

  if ($header =~ /\$count/ ||
      $footer =~ /\$count/ ||
      $format =~ /\$count/ ||
      (defined $params->{hidenull} && $params->{hidenull} eq 'on')) {

    if ($params->{nrtopics}) {
      unless ($params->{_nrTopics}) {
        my %nrTopics = ();
        foreach my $item (split(/\s*,\s*/, $params->{nrtopics})) {
          if ($item =~ /^(.*):(.*)$/) {
            $nrTopics{$1} = $2;
          }
        }
        $params->{_nrTopics} = \%nrTopics;
      }
      $nrTopics = $params->{_nrTopics}{$this->{name}} || 0;
    } else {
      $nrTopics = $this->countTopics($filter);
    }
  }

  return $subResult
    if defined $params->{hidenull} && $params->{hidenull} eq 'on' && !$nrTopics;

  my $nrLeafs;

  if ($header =~ /\$leafs/ ||
      $footer =~ /\$leafs/ ||
      $format =~ /\$leafs/) {

    if ($params->{nrleafs}) {
      unless ($params->{_nrLeafs}) {
        my %nrLeafs = ();
        foreach my $item (split(/\s*,\s*/, $params->{nrleafs})) {
          if ($item =~ /^(.*):(.*)$/) {
            $nrLeafs{$1} = $2;
          }
        }
        $params->{_nrLeafs} = \%nrLeafs;
      }
      $nrLeafs = $params->{_nrLeafs}{$this->{name}} || 0;
    } else {
      $nrLeafs = $this->countLeafs($filter);
    }
  }

  return $subResult
    if defined $params->{duplicates} && $params->{duplicates} eq 'off' && $params->{seen}{$this->{name}};

  # DEPRECATED: use filter instead
  my $tagFilter = $params->{tags};
  if ($tagFilter) {
    #writeDebug("tagFilter=$tagFilter");
    $this->getTagsOfTopics(); # CAUTION: depends on filter
    foreach my $tag (split(/\s*,\s*/, $tagFilter)) {
      return $subResult unless defined $this->{_tags}{$tag};
    }
  }

  $params->{seen}{$this->{name}} = 1;

  my $isCyclic = 0;
  $isCyclic = $this->isCyclic() if $format =~ /\$cyclic/;

  my $indent = $params->{indent} || '   ';
  $indent = $indent x $depth;

  my $iconUrl = $this->getIconUrl();

  my $tags = '';
  if ($header =~ /\$tags/ ||
      $footer =~ /\$tags/ ||
      $format =~ /\$tags/) {
    #writeDebug("getting tags");
    my @tags = $this->getTagsOfTopics(); # CAUTION: depends on filter
    $tags = join(', ', @tags);
  }

  my $parents = '';
  if ($header =~ /\$parents/ ||
      $footer =~ /\$parents/ ||
      $format =~ /\$parents/) {
    $parents = join(', ', map {$_->{name}} $this->getParents());
  }

  my $distToRoot = 0;
  if ($header =~ /\$depth/ ||
      $footer =~ /\$depth/ ||
      $format =~ /\$depth/) {
    $distToRoot = abs($this->distance($this->{hierarchy}{_top}));
  }

  my $breadCrumbs = '';
  if ($header =~ /\$breadcrumbs/ ||
      $footer =~ /\$breadcrumbs/ ||
      $format =~ /\$breadcrumbs/) {
    $breadCrumbs = join(", ", map {$_->{name}} $this->getBreadCrumbs());
  }

  my $truncTitle = $this->title;
  $truncTitle =~ s/^$parentTitle\b\s*[\-,\/]?\s*// if $parentTitle;

  if ($subResult) {
    $header = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($header,
      'web'=>$this->{hierarchy}{web}, 
      'origweb'=>$this->{origWeb} || '', 
      'topic'=>$this->{name},
      'name'=>$this->{name},
      'summary'=>$this->summary,
      'title'=>$this->title,
      'trunctitle'=>$truncTitle,
      'siblings'=>$nrSiblings,
      'count'=>$nrTopics,
      'index'=>$index,
      'subcats'=>$nrChildren,
      'call'=>$$nrCalls,
      'leafs'=>$nrLeafs,
      'cyclic'=>$isCyclic,
      'id'=>$this->{id},
      'depth'=>$distToRoot,
      'indent'=>$indent,
      'icon'=>$iconUrl,
      'tags'=>$tags,
      'parents'=>$parents,
      'breadcrumbs'=>$breadCrumbs,
      'order'=>$this->order,
      'isexpanded'=>$isExpanded?'true':'false',
    );
    $footer = Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($footer,
      'web'=>$this->{hierarchy}{web}, 
      'origweb'=>$this->{origWeb} || '', 
      'topic'=>$this->{name},
      'name'=>$this->{name},
      'summary'=>$this->summary,
      'title'=>$this->title,
      'trunctitle'=>$truncTitle,
      'siblings'=>$nrSiblings,
      'count'=>$nrTopics,
      'index'=>$index,
      'subcats'=>$nrChildren,
      'call'=>$$nrCalls,
      'leafs'=>$nrLeafs,
      'cyclic'=>$isCyclic,
      'id'=>$this->{id},
      'depth'=>$distToRoot,
      'indent'=>$indent,
      'icon'=>$iconUrl,
      'tags'=>$tags,
      'parents'=>$parents,
      'breadcrumbs'=>$breadCrumbs,
      'order'=>$this->order,
      'isexpanded'=>$isExpanded?'true':'false',
    );
    $subResult = $header.$subResult.$footer;
  }

  return Foswiki::Plugins::ClassificationPlugin::Core::_expandVariables($format, 
    'link'=>($this->{name} =~ /^(TopCategory|BottomCategory)$/)?
      "<b>".$this->title."</b>":$this->getLink(),
    'origlink'=>($this->{name} =~ /^(TopCategory|BottomCategory)$/)?
      "<b>".$this->title."</b>":$this->getLink(0),
    'url'=>($this->{name} =~ /^(TopCategory|BottomCategory)$/)?"":
      $this->getUrl(),
    'origurl'=>($this->{name} =~ /^(TopCategory|BottomCategory)$/)?"":
      $this->getUrl(0),
    'web'=>$this->{hierarchy}{web}, 
    'origweb'=>$this->{origWeb} || '', 
    'topic'=>$this->{name},
    'name'=>$this->{name},
    'summary'=>$this->summary,
    'title'=>$this->title,
    'trunctitle'=>$truncTitle,
    'children'=>$subResult,
    'siblings'=>$nrSiblings,
    'count'=>$nrTopics,
    'index'=>$index,
    'subcats'=>$nrChildren,
    'call'=>$$nrCalls,
    'leafs'=>$nrLeafs,
    'cyclic'=>$isCyclic,
    'id'=>$this->{id},
    'depth'=>$distToRoot,
    'indent'=>$indent,
    'icon'=>$iconUrl,
    'tags'=>$tags,
    'parents'=>$parents,
    'breadcrumbs'=>$breadCrumbs,
    'order'=>$this->order,
    'isexpanded'=>$isExpanded?'true':'false',
  );
}

###############################################################################
# from Foswiki.pm
sub urlDecode {
    my $text = shift;

    $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

    return $text;
}

1;
