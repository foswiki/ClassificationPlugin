# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2013-2019 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ClassificationPlugin::JSTreeConnector;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Meta ();
use Foswiki::Sandbox ();
use Foswiki::Plugins::ClassificationPlugin ();
use JSON ();
use Error qw( :try );

use constant TRACE => 0; # toggle me

################################################################################
# static
sub writeDebug {
  print STDERR $_[0]."\n" if TRACE;
}

################################################################################
# constructor
sub new {
  my $class = shift;

  return bless({@_}, $class);
}

################################################################################
# dispatch all handler_... methods
sub dispatchAction {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my $theWeb = $request->param('web') || $session->{webName};
  $theWeb = Foswiki::Sandbox::untaint($theWeb, \&Foswiki::Sandbox::validateWebName) || '';

  my $result;
  try {
    my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($theWeb);
    throw Error::Simple("Hierarchy not found") unless defined $hierarchy;

    my $theAction = $request->param('action');
    throw Error::Simple("No action specified") unless defined $theAction;

    my $method = "handle_".$theAction;
    throw Error::Simple("Unknown action") unless $this->can($method);

    $result = $this->$method($session, $hierarchy);

    $response->header(
      -status => 200,
      -content_type => "text/json",
    );

  } catch Error::Simple with {
    my $error = shift;

    $result = {
      "type" => "error",
      "title" => "Error",
      "message" => $error->{-text}
    };

    $response->header(
      -status => 500,
      -content_type => "text/plain",
    );
  };

  $response->print(JSON::to_json($result)) if defined $result;
  
  return;
}

################################################################################
sub getChildren {
  my ($this, $session, $cat, $selected, $depth, $displayCounts, $sort, $seen) = @_;

  return if $depth == 0;

  #writeDebug("getChildren($cat->{name}, $depth)");

  $seen ||= {};
  return if $seen->{$cat};
  $seen->{$cat} = 1;

  my @result = ();

  my @children = $cat->getChildren;

  if ($sort eq 'on' || $sort eq 'order') {
    @children = sort {
      $a->order <=> $b->order ||
      lc($a->title) cmp lc($b->title)
    } @children;
  } elsif ($sort eq 'title') {
    @children = sort {
      lc($a->title) cmp lc($b->title)
    } @children;
  } elsif ($sort eq 'name') {
    @children = sort {
      lc($a->{name}) cmp lc($b->{name})
    } @children;
  }

  foreach my $child (@children) {
    next if $child->{name} eq 'BottomCategory';
    my $nrChildren = scalar(grep {!/^BottomCategory$/} keys %{$child->{children}});
    my $nrTopics = $displayCounts?$child->countTopics():0;
    my %state = ();
    foreach my $selCat (@$selected) {
      if ($child eq $selCat) {
        $state{"selected"} = $JSON::true;
      } else {
        if ($child->subsumes($selCat)) {
          $state{"opened"} = $JSON::true;
        }
      }
    }

    my $icon = $child->getIconUrl() || $child->icon || "fa-folder-o";
    $icon = "fa $icon" if $icon =~ /^fa\-/;
    $icon = "ma $icon" if $icon =~ /^ma\-/;

    my $record = {
      "text" => $child->title.($nrTopics?"<span class='jstree-count'>($nrTopics)</span>":""),
      "icon" => $icon,
      "id" => $child->{name},
      "a_attr" => {
        "href" => $child->getUrl(),
        "class" => $child->{name},
        "data-edit-url" =>  Foswiki::Func::getScriptUrl($child->{origWeb}, $child->{name}, "edit", 
          t => time(),
          #redirectto => Foswiki::Func::getScriptUrl($session->{webName}, $session->{topicName}, "view")
        ), 
        "data-title" => $child->title(),
      },
      state => \%state,
    };
    if ($state{"opened"}) {
      $record->{children} = $this->getChildren($session, $child, $selected, $depth-1, $displayCounts, $sort, $seen);
    } else {
      if ($nrChildren) {
        $record->{children} = $JSON::true;
      }
    }
    push @result, $record;
  }

  $seen->{$cat} = 0; # prevent cycles, but allow this branch to be displayed somewhere else

  return \@result;
}


################################################################################
# handlers
################################################################################

################################################################################
sub handle_refresh {
  my ($this, $session, $hierarchy) = @_;

  writeDebug("refresh called for ".$hierarchy->{web});

  $hierarchy->init;
  $hierarchy->finish;

  return {
    type => "notice",
    title => $session->i18n->maketext("Success"),
    message => $session->i18n->maketext("refreshed hierarchy in web [_1]", $hierarchy->{web}),
  };
}

################################################################################
sub handle_get_children {
  my ($this, $session, $hierarchy) = @_;

  #writeDebug("get_children called");

  my $request = Foswiki::Func::getRequestObject();

  my $catName = $request->param('cat') || "TopCategory";
  my @select = $request->multi_param('select');
  my $maxDepth = $request->param('maxDepth');
  $maxDepth = -1 unless defined $maxDepth;

  my $displayCounts = Foswiki::Func::isTrue(scalar $request->param('counts'), 0);

  my $sort = $request->param('sort');
  $sort = 'on' if !defined($sort) || $sort !~ /^(on|title|order|name)$/;

  #writeDebug("select=@select") if @select;

  my $cat = $hierarchy->getCategory($catName);
  throw Error::Simple("Unknown category") 
    unless defined $cat;

  my %select = ();
  foreach (@select) {
    foreach my $item (split(/\s*,\s+/)) {
      my $cat = $hierarchy->getCategory($item);
      $select{$item} = $cat if defined $cat;
    }
  }
  @select = values %select; 

  return $this->getChildren($session, $cat, \@select, $maxDepth, $displayCounts, $sort);
}

################################################################################
sub handle_search {
  my ($this, $session, $hierarchy) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my %cats = ();

  my $search = join(".*", split(/\s+/, $request->param("title")));

  $hierarchy->filterCategories({
    casesensitive => "off",
    title => $search,
    callback => sub {
      my $cat = shift;
      $cats{$cat->{name}} = 1;
      foreach my $parent ($cat->getAllParents) {
        $cats{$parent} = 1;
      }
    }
  });

  return [keys %cats];
}

################################################################################
sub handle_move_node {
  my ($this, $session, $hierarchy) = @_;

  #writeDebug("move_node called");

  my $request = Foswiki::Func::getRequestObject();

  my $catName = $request->param("cat");
  throw Error::Simple("No category") unless defined $catName;

  my $cat = $hierarchy->getCategory($catName);
  throw Error::Simple("Unknown category") unless defined $cat;

  my $newParentName = $request->param("parent") || "TopCategory";
  my $newParent = $hierarchy->getCategory($newParentName);
  throw Error::Simple("Unknown category") unless defined $newParent;

  my $oldParentName = $request->param("oldParent") || "TopCategory";
  my $oldParent = $hierarchy->getCategory($oldParentName);
  throw Error::Simple("Unknown category") unless defined $oldParent;

  my $doCopy = $request->param("copy") || 0;
  throw Error::Simple("Copy not implemented yet") if $doCopy;

  # reparent
  my ($meta) = Foswiki::Func::readTopic($cat->{origWeb}, $cat->{name});
  throw Error::Simple("Woops, category not found")
    unless Foswiki::Func::topicExists($cat->{origWeb}, $cat->{name});

  $meta = $cat->reparent($newParent, $oldParent, $meta);
  throw Error::Simple("Woops, can't reparent category") unless defined $meta;
  
  # reorder 
  my $nextCatName = $request->param("next");
  my $nextCat;
  if ($nextCatName) {
    $nextCat = $hierarchy->getCategory($nextCatName);
    throw Error::Simple("Unknown category") unless defined $nextCat;
  }

  my $prevCatName = $request->param("prev");
  my $prevCat;
  if ($prevCatName) {
    $prevCat = $hierarchy->getCategory($prevCatName);
    throw Error::Simple("Unknown category") unless defined $prevCat;
  }

  if (defined $nextCat && defined $prevCat) {
    #writeDebug("catName=$catName, newParentName=$newParentName, oldParentName=$oldParentName, nextCatName=$nextCatName, prevCatName=$prevCatName, doCopy=$doCopy");

    my @sortedCats = 
      sort {
        ($a->{name} eq $catName && $b->{name} eq $prevCatName)?1:
        ($a->{name} eq $prevCatName && $b->{name} eq $catName)?-1:
        ($a->{name} eq $catName && $b->{name} eq $nextCatName)?-1:
        ($a->{name} eq $nextCatName && $b->{name} eq $catName)?1:
        $a->order <=> $b->order || $a->title cmp $b->title;
      } grep {$_->{name} !~ /^BottomCategory$/} values %{$newParent->{children}};

    #print STDERR "sortedCats=".join(", ", map {$_->{name}} @sortedCats)."\n";

    my $index = 10;
    foreach my $item (@sortedCats) {
      try {
        my ($meta) = Foswiki::Func::readTopic($item->{origWeb}, $item->{name});
        $item->order($index, $meta);
        Foswiki::Func::saveTopic($item->{origWeb}, $item->{name}, $meta);
      } catch Foswiki::AccessControlException with {
        throw Error::Simple("No write access");  
      };
      $index+= 10;
    }
  }

  try {
    Foswiki::Func::saveTopic($cat->{origWeb}, $cat->{name}, $meta);
  } catch Foswiki::AccessControlException with {
    throw Error::Simple("No write access");  
  };

  # init'ing hierarchy 
  if ($cat->{hierarchy}{web} ne $cat->{origWeb}) {
    $hierarchy->init;
    $hierarchy->finish;
  }

  return {
    type => "notice",
    title => $session->i18n->maketext("Success"),
    message => $session->i18n->maketext("moved [_1] to [_2]", $cat->title, $newParent->title),
    id => $cat->{name},
  };
}

################################################################################
sub handle_rename_node {
  my ($this, $session, $hierarchy) = @_;

  #writeDebug("rename_node called");

  my $request = Foswiki::Func::getRequestObject();

  my $catName = $request->param("cat");
  throw Error::Simple("No category") unless defined $catName;

  my $cat = $hierarchy->getCategory($catName);
  throw Error::Simple("Unknown category") unless defined $cat;

  my $newTitle = $request->param("title");
  $newTitle = $cat->{name} if !defined($newTitle) || $newTitle eq "";
  $newTitle =~ s/^\s+|\s+$//g;

  my ($meta) = Foswiki::Func::readTopic($cat->{origWeb}, $cat->{name});
  my $field = $meta->get('FIELD', 'TopicTitle'); 
  throw Error::Simple("No TopicTitle field") unless $field;

  my $oldTitle = $field->{value};
  $field->{value} = $newTitle;

  $meta->putKeyed('FIELD', $field);

  try {
    Foswiki::Func::saveTopic($cat->{origWeb}, $cat->{name}, $meta);
  } catch Foswiki::AccessControlException with {
    throw Error::Simple("No write access");  
  };

  # init'ing hierarchy 
  if ($cat->{hierarchy}{web} ne $cat->{origWeb}) {
    $hierarchy->init;
    $hierarchy->finish;
  }

  return {
    type => "notice",
    title => $session->i18n->maketext("Success"),
    message => $session->i18n->maketext("changed title to [_1]", $newTitle),
    id => $cat->{name},
  };
}

################################################################################
sub handle_create_node {
  my ($this, $session, $hierarchy) = @_;

  #writeDebug("create_node called");

  my $request = Foswiki::Func::getRequestObject();

  my $catName = $request->param("cat");
  throw Error::Simple("No category") unless defined $catName;

  my $title = $request->param("title") || $catName;

  my $cat = $hierarchy->getCategory($catName);
  throw Error::Simple("Category already exists") if defined $cat;

  my $parentName = $request->param("parent") || '';
  if ($parentName) {
    throw Error::Simple("Parent category does not exists") 
      unless defined $hierarchy->getCategory($parentName);
  }

  my $position = $request->param("position");
  $position = '' unless defined $position;
  #writeDebug("catName=$catName, parentName=$parentName, position=$position, title=$title");

  my $tmplObj;
  my $tmplText;

  ($tmplObj, $tmplText) = Foswiki::Func::readTopic("Applications.ClassificationApp", "CategoryTemplate")
    if Foswiki::Func::topicExists("Applications.ClassificationApp", "CategoryTemplate");

  my $obj = Foswiki::Meta->new($session, $hierarchy->{web}, $catName);
  $obj->text($tmplText) if defined $tmplText;
  
  # add form
  $obj->putKeyed("FORM", { name => "Applications.ClassificationApp.Category" });
  $obj->putKeyed("FIELD", {
    name => "TopicType",
    title => "TopicType",
    value => "Category, CategorizedTopic, WikiTopic",
  });
  $obj->putKeyed("FIELD", {
    name => "TopicTitle",
    title => "<nop>TopicTitle",
    value => "$title",
  });
  $obj->putKeyed("FIELD", {
    name => "Category",
    title => "Category",
    value => "$parentName",
  });
  $obj->putKeyed("FIELD", {
    name => "Order",
    title => "Order",
    value => "$position",
  });

  $obj->save();
  #writeDebug("new category object:".$obj->getEmbeddedStoreForm());

  $hierarchy->init;
  $hierarchy->finish;

  return {
    type => "notice",
    title => $session->i18n->maketext("Success"),
    message => $session->i18n->maketext("created category [_1]", $title),
    id => $catName
  };
}

################################################################################
sub handle_remove_node {
  my ($this, $session, $hierarchy) = @_;

  #writeDebug("remove_node called");

  my $request = Foswiki::Func::getRequestObject();

  my $catName = $request->param("cat");
  throw Error::Simple("No category") unless defined $catName;

  my $cat = $hierarchy->getCategory($catName); 
  throw Error::Simple("Unknown category") 
    unless defined $cat;

  # SMELL: duplicates code in with Foswiki::UI::Rename
  my $fromWeb = $hierarchy->{web};
  my $fromTopic = $catName;
  my $toWeb = $Foswiki::cfg{TrashWebName};
  my $toTopic = $catName;
  my $n = 1;
  while (Foswiki::Func::topicExists($toWeb, $toTopic)) {
    $toTopic = $toTopic . $n;
    $n++;
  }

  #writeDebug("moving $fromWeb.$fromTopic to $toWeb.$toTopic");

  Foswiki::Func::moveTopic($fromWeb, $fromTopic, $toWeb, $toTopic);

  return {
    type => "notice",
    title => $session->i18n->maketext("Success"),
    message => $session->i18n->maketext("deleted category [_1]", $cat->title),
    id => $catName
  };
}

1;
