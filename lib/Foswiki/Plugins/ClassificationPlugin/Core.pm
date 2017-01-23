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

package Foswiki::Plugins::ClassificationPlugin::Core;

use strict;
use warnings;

use constant TRACE => 0; # toggle me
use constant FIXFORMFIELDS => 1; # work around a bug in Foswiki
use Foswiki::Plugins::ClassificationPlugin ();
use Foswiki::Plugins::DBCachePlugin ();
use Foswiki::Form ();
use Foswiki::OopsException ();
use Foswiki::Contrib::MailerContrib ();
use Error qw( :try );
use Carp qw(confess cluck);

###############################################################################
sub new {
  my $class = shift;

  my $this = bless({
      purgeMode => 0,
      beforeResponsiblePerson => '',
      modTimeStamps => {},
      loadTimeStamps => {},
      hierarchies => {},
      cachedIndexFields => {},
      changedCats => {},
      @_
    },
    $class
  );

  return $this;
}

###############################################################################
sub finish {
  my $this = shift;

  #_writeDebug("called finish()");
  foreach my $hierarchy (values %{$this->{hierarchies}}) {
    next unless defined $hierarchy;
    $hierarchy->finish();
  }

  undef $this->{hierarchies};
  undef $this->{modTimeStamps};
  undef $this->{changedCats};
  undef $this->{loadTimeStamps};

  #_writeDebug("done finish()");
}

###############################################################################
sub OP_subsumes {
  my ($this, $r, $l, $map) = @_;
  my $lval = $l->matches( $map );
  my $rval = $r->matches( $map );
  return 0 unless ( defined $lval  && defined $rval);

  my $session = $Foswiki::Plugins::SESSION;
  my $web = Foswiki::Plugins::DBCachePlugin::getCore->currentWeb() || $session->{webName};
  my $hierarchy = $this->getHierarchy($web);
  return $hierarchy->subsumes($lval, $rval);
}

###############################################################################
sub OP_isa {
  my ($this, $r, $l, $map) = @_;
  my $lval = $l->matches( $map );
  my $rval = $r->matches( $map );

  return 0 unless ( defined $lval  && defined $rval);

  my $session = $Foswiki::Plugins::SESSION;
  my $web = Foswiki::Plugins::DBCachePlugin::getCore->currentWeb() || $session->{webName};
  my $hierarchy = $this->getHierarchy($web);
  my $cat = $hierarchy->getCategory($rval);
  return 0 unless $cat;

  return ($cat->contains($lval))?1:0;
}

###############################################################################
sub OP_distance {
  my ($this, $r, $l, $map) = @_;
  my $lval = $l->matches( $map );
  my $rval = $r->matches( $map );

  return 0 unless ( defined $lval  && defined $rval);

  my $session = $Foswiki::Plugins::SESSION;
  my $web = Foswiki::Plugins::DBCachePlugin::getCore->currentWeb() || $session->{webName};
  my $hierarchy = $this->getHierarchy($web);
  my $dist = $hierarchy->distance($lval, $rval);

  return $dist || 0;
}

###############################################################################
sub handleSIMILARTOPICS {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  #_writeDebug("called handleSIMILARTOPICS()");
  my $thisTopic = $params->{_DEFAULT} || $params->{topic} || $session->{topicName};
  my $thisWeb = $params->{web} || $session->{webName};
  my $theFormat = $params->{format} || '$topic';
  my $theHeader = $params->{header} || '';
  my $theFooter = $params->{footer} || '';
  my $theSep = $params->{separator};
  my $theLimit = $params->{limit};
  my $theSkip = $params->{skip};
  my $theThreshold = $params->{threshold} || 0.3;

  $theThreshold =~ s/[^\d\.]//go;
  $theThreshold = 0.3 unless $theThreshold;
  $theThreshold = $theThreshold/100 if $theThreshold > 1.0;
  $theSep = ', ' unless defined $theSep;
  $theLimit = 10 unless defined $theLimit;

  my $hierarchy = $this->getHierarchy($thisWeb);
  my @similarTopics = $hierarchy->getSimilarTopics($thisTopic, $theThreshold);
  return '' unless @similarTopics;

  my %wmc = ();
  map {$wmc{$_} = $hierarchy->computeSimilarity($thisTopic, $_)} @similarTopics;
  @similarTopics = sort {$wmc{$b} <=> $wmc{$a}} @similarTopics;

  # format result
  my @lines;
  my $index = 0;
  foreach my $topic (@similarTopics) {
    $index++;
    next if $theSkip && $index <= $theSkip;
    last if $theLimit && $index > $theLimit;
    push @lines, _expandVariables($theFormat,
      'topic'=>$topic,
      'web'=>$thisWeb,
      'index'=>$index,
      'similarity'=> int($wmc{$topic}*1000)/10,
    );
  }

  return '' unless @lines;
  $theHeader = _expandVariables($theHeader, count=>$index);
  $theFooter = _expandVariables($theFooter, count=>$index);
  $theSep = _expandVariables($theSep);

  return $theHeader.join($theSep, @lines).$theFooter;
}

###############################################################################
sub handleHIERARCHY {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  #_writeDebug("called handleHIERARCHY(".$params->stringify().")");

  my $thisWeb = $params->{_DEFAULT} || $params->{web} || $session->{webName};
  $thisWeb =~ s/\./\//go;

  my $hierarchy = $this->getHierarchy($thisWeb);
  return $hierarchy->traverse($params);
}

###############################################################################
sub handleISA {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  #_writeDebug("called handleISA()");
  my $thisWeb = $params->{web} || $session->{webName};
  my $thisTopic = $params->{_DEFAULT} || $params->{topic} || $session->{topicName};
  my $theCategory = $params->{cat} || 'TopCategory';

  #_writeDebug("topic=$thisTopic, theCategory=$theCategory");

  return 1 if $theCategory =~ /^(Top|TopCategory)$/oi;
  return 0 if $theCategory =~ /^(Bottom|BottomCategory)$/oi;
  return 0 unless $theCategory;

  ($thisWeb, $thisTopic) =
    Foswiki::Func::normalizeWebTopicName($thisWeb, $thisTopic);

  my $hierarchy = $this->getHierarchy($thisWeb);

  foreach my $catName (split(/\s*,\s*/, $theCategory)) {
    #_writeDebug("testing $catName");
    my $cat = $hierarchy->getCategory($catName);
    next unless $cat;
    return 1 if $cat->contains($thisTopic);
  }
  #_writeDebug("not found");

  return 0;
}

###############################################################################
sub handleSUBSUMES {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  my $thisWeb = $params->{web} || $session->{webName};
  my $theCat1 = $params->{_DEFAULT} || $session->{topicName};
  my $theCat2 = $params->{cat} || '';

  #_writeDebug("called handleSUBSUMES($theCat1, $theCat2)");

  return 0 unless $theCat2;

  my $hierarchy = $this->getHierarchy($thisWeb);
  my $cat1 = $hierarchy->getCategory($theCat1);
  return 0 unless $cat1;

  my $result = 0;
  foreach my $catName (split(/\s*,\s*/,$theCat2)) {
    $catName =~ s/^\s+//g;
    $catName =~ s/\s+$//g;
    next unless $catName;
    my $cat2 = $hierarchy->getCategory($catName);
    next unless $cat2;
    $result = $cat1->subsumes($cat2) || 0;
    last if $result;
  }

  #_writeDebug("result=$result");

  return $result;
}

###############################################################################
sub handleDISTANCE {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  my $thisWeb = $params->{web} || $session->{webName};
  my $theFrom = $params->{_DEFAULT} || $params->{from} || $session->{topicName};
  my $theTo = $params->{to} || 'TopCategory';
  my $theAbs = $params->{abs} || 'off';
  my $theFormat = $params->{format} || '$dist';
  my $theUndef = $params->{undef} || '';

  #_writeDebug("called handleDISTANCE($theFrom, $theTo)");

  my $hierarchy = $this->getHierarchy($thisWeb);
  my $distance = $hierarchy->distance($theFrom, $theTo);

  return $theUndef unless defined $distance;

  $distance = abs($distance) if $theAbs eq 'on';

  #_writeDebug("distance=$distance");

  my $result = $theFormat;
  $result =~ s/\$dist/$distance/g;

  return $result;
}

###############################################################################
sub handleCATINFO {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  #_writeDebug("called handleCATINFO(".$params->stringify().")");
  my $theCat = $params->{cat};
  my $theFormat = $params->{format} || '$link';
  my $theSep = $params->{separator};
  my $theHeader = $params->{header} || '';
  my $theFooter = $params->{footer} || '';
  my $thisWeb = $params->{web} || $session->{webName};
  my $thisTopic = $params->{_DEFAULT} || $params->{topic};
  my $theSubsumes = $params->{subsumes} || '';
  my $theParentSubsumes = $params->{parentsubsumes} || '';
  my $theSortChildren = $params->{sortchildren} || 'off';
  my $theMaxChildren = $params->{maxchildren} || 0;
  my $theHideNull = $params->{hidenull} || 'off';
  my $theNull = $params->{null} || '';
  my $theExclude = $params->{exclude} || '';
  my $theInclude = $params->{include} || '';
  my $theTruncate = $params->{truncate} || '';
  my $theMatchAttr = $params->{matchattr} || 'name';
  my $theMatchCase = $params->{matchcase} || 'on';
  my $theLimit = $params->{limit};
  my $theSkip = $params->{skip};

  $theLimit =~ s/[^\d]//g if defined $theLimit;
  $theSkip =~ s/[^\d]//g if defined $theSkip;

  $theMatchAttr = 'name' unless $theMatchAttr =~ /^(name|title)$/;

  $theSep = ', ' unless defined $theSep;
  $theMaxChildren =~ s/[^\d]//go;
  $theMaxChildren = 0 unless defined $theMaxChildren;

  my $hierarchy;
  my $categories;
  if ($theCat) { # cats mode
    if ($thisWeb eq 'any') {
      $hierarchy = $this->findHierarchy($theCat);
      return '' unless $hierarchy;
      $thisWeb = $hierarchy->{web};
    } else {
      my $catWeb;
      ($catWeb, $theCat) = 
        Foswiki::Func::normalizeWebTopicName($thisWeb, $theCat);
      $thisWeb = $catWeb unless defined $thisWeb;
      $hierarchy = $this->getHierarchy($thisWeb);
    }
    push @$categories, $theCat;
  } elsif ($thisTopic) { # topic mode
    ($thisWeb, $thisTopic) = 
      Foswiki::Func::normalizeWebTopicName($thisWeb, $thisTopic);
    $hierarchy = $this->getHierarchy($thisWeb);
    $categories = $hierarchy->getCategoriesOfTopic($thisTopic) if $hierarchy;
  } else { # find mode
    $hierarchy = $this->getHierarchy($thisWeb);
    @$categories = $hierarchy->getCategoryNames();
  }

  return _expandVariables($theNull) unless $hierarchy;
  return _expandVariables($theNull)  unless $categories;
  #_writeDebug("categories=".join(', ', @$categories));

  my @result;
  my $doneBreadCrumbs = 0;
  my $index = 0;
  $theSubsumes =~ s/^\s+//go;
  $theSubsumes =~ s/\s+$//go;
  $theParentSubsumes =~ s/^\s+//go;
  $theParentSubsumes =~ s/\s+$//go;
  my $subsumesCat = $hierarchy->getCategory($theSubsumes);
  my $parentSubsumesCat = $hierarchy->getCategory($theParentSubsumes);

  foreach my $catName (sort @$categories) {
    next if $theCat && $theCat ne 'TopCategory' && $catName =~ /BottomCategory|TopCategory/;
    my $category = $hierarchy->getCategory($catName);
    next unless $category;

    if ($theMatchCase eq 'on') {
      next if $theExclude && $category->{$theMatchAttr} =~ /^($theExclude)$/;
      next if $theInclude && $category->{$theMatchAttr} !~ /^($theInclude)$/;
    } else {
      next if $theExclude && $category->{$theMatchAttr} =~ /^($theExclude)$/i;
      next if $theInclude && $category->{$theMatchAttr} !~ /^($theInclude)$/i;
    }

    #_writeDebug("found $catName");

    # skip catinfo from another branch of the hierarchy
    next if $subsumesCat && !$hierarchy->subsumes($subsumesCat, $category);

    $index++;
    next if $theSkip && $index <= $theSkip;

    my $line = $theFormat;

    my @parents;
    if ($line =~ /\$parent/) {
      @parents = sort {uc($a->title) cmp uc($b->title)} $category->getParents($parentSubsumesCat);
    }

    my $parentLinks = '';
    if ($line =~ /\$parents?\b/ || $line =~ /\$parents?links?/) {
      my @links = ();
      foreach my $parent (@parents) {
        push @links, $parent->getLink();
      }
      $parentLinks = join($theSep, @links);
    }

    my $parentsName = '';
    if ($line =~ /\$parents?names?/) {
      my @names = ();
      foreach my $parent (@parents) {
        push @names, $parent->{name};
      }
      $parentsName = join($theSep, @names);
    }

    my $parentsTitle = '';
    if ($line =~ /\$parents?title/) {
      my @titles = ();
      foreach my $parent (@parents) {
        push @titles, $parent->title;
      }
      $parentsTitle = join($theSep, @titles);
    }

    my $parentUrls = '';
    if ($line =~ /\$parents?urls?/) {
      my @urls = ();
      foreach my $parent (@parents) {
        push @urls, $parent->getUrl();
      }
      $parentUrls = join($theSep, @urls);
    }

    my $breadCrumbs = '';
    my $breadCrumbNames = '';
    if ($line =~ /\$(breadcrumb(name)?)s?/ && !$doneBreadCrumbs) {

      my @breadCrumbs = $category->getBreadCrumbs();
      if ($theExclude) {
        @breadCrumbs = grep { $_->{name} !~ /^($theExclude)$/ } @breadCrumbs;
      }

      my @breadCrumbLinks = ();
      my @breadCrumbNames = ();

      if (@breadCrumbs) {
        my $firstParent = $breadCrumbs[-1];

        if ($firstParent->redirect && $thisTopic && $firstParent->redirect eq $thisTopic) {
          pop @breadCrumbs;
        }

        @breadCrumbLinks = map {$_->getLink()} @breadCrumbs;
        @breadCrumbNames = map {$_->{name}} @breadCrumbs;
      }

      unless ($theCat) {
        if ($thisTopic && Foswiki::Func::topicExists($thisWeb, $thisTopic)) {
          push @breadCrumbLinks, "[[$thisWeb.$thisTopic]]";
          push @breadCrumbNames, $thisTopic;
        }
      }

      $breadCrumbs = join($theSep, @breadCrumbLinks);
      $breadCrumbNames = join($theSep, @breadCrumbNames);
      $doneBreadCrumbs = 1;
    }

    my @children;
    my $moreChildren = '';
    if ($line =~ /\$children/) {
      @children = sort {uc($a->title) cmp uc($b->title)} $category->getChildren();
      @children = grep {$_->{name} ne 'BottomCategory'} @children;

      if ($theHideNull eq 'on') {
        @children = grep {$_->countLeafs() > 0} 
          @children;
      }

      if ($theSortChildren eq 'on') {
        @children = 
          sort {$b->countLeafs() <=> $a->countLeafs() || 
                $a->title cmp $b->title} 
            @children;
      }

      if ($theMaxChildren && $theMaxChildren < @children) {
        if (splice(@children, $theMaxChildren)) {
          $moreChildren = $params->{morechildren} || '';
        }
      }
    }

    my $children = '';
    if ($line =~ /\$children(links)?\b/) {
      my @links = ();
      foreach my $child (@children) {
        push @links, $child->getLink();
      }
      $children = join($theSep, @links);
    }

    my $childrenName = '';
    if ($line =~ /\$children?names?/) {
      my @names = ();
      foreach my $child (@children) {
        push @names, $child->{name};
      }
      $childrenName = join($theSep, @names);
    }

    my $childrenTitle = '';
    if ($line =~ /\$childrentitle/) {
      my @titles = ();
      foreach my $child (@children) {
        push @titles, $child->title;
      }
      $childrenTitle = join($theSep, @titles);
    }


    my $childrenUrls = '';
    if ($line =~ /\$childrenurls?/) {
      my @urls = ();
      foreach my $child (@children) {
        push @urls, $child->getUrl();
      }
      $childrenUrls = join($theSep, @urls);
    }

    my $tags = '';
    if ($line =~ /\$tags/) {
      $tags = join($theSep, sort $category->getTagsOfTopics());
    }


    my $isCyclic = 0;
    $isCyclic = $category->isCyclic() if $theFormat =~ /\$cyclic/;

    my $countLeafs = '';
    $countLeafs = $category->countLeafs() if $theFormat=~ /\$leafs/;

    my $nrTopics = '';
    $nrTopics = $category->countTopics() if $theFormat=~ /\$count/;

    my $title = $category->title || $catName;
    my $link = $category->getLink();
    my $origlink = $category->getLink(0);
    my $origurl = $category->getUrl(0);
    my $url = $category->getUrl();
    my $summary = $category->summary || '';

    my $icon = $category->getIcon();
    my $iconUrl = $category->getIconUrl();

    my $truncTitle = $title;
    $truncTitle =~ s/$theTruncate// if $theTruncate;

    $line =~ s/\$more/$moreChildren/g;
    $line =~ s/\$index/$index/g;
    $line =~ s/\$link/$link/g;
    $line =~ s/\$origlink/$origlink/g;
    $line =~ s/\$url/$url/g;
    $line =~ s/\$origurl/$origurl/g;
    $line =~ s/\$web/$thisWeb/g;
    $line =~ s/\$origweb/$category->{origWeb}/g;
    $line =~ s/\$order/$category->{order}/g;
    $line =~ s/\$(name|topic)/$catName/g;
    $line =~ s/\$title/$title/g;
    $line =~ s/\$trunctitle/$truncTitle/g;
    $line =~ s/\$summary/$summary/g;
    $line =~ s/\$parents?name/$parentsName/g;
    $line =~ s/\$parents?title/$parentsTitle/g;
    $line =~ s/\$parents?links?/$parentLinks/g;
    $line =~ s/\$parents?urls?/$parentUrls/g;
    $line =~ s/\$parents?/$parentLinks/g;
    $line =~ s/\$cyclic/$isCyclic/g;
    $line =~ s/\$leafs/$countLeafs/g;
    $line =~ s/\$count/$nrTopics/g;
    $line =~ s/\$breadcrumbnames?/$breadCrumbNames/g;
    $line =~ s/\$breadcrumbs?/$breadCrumbs/g;
    $line =~ s/\$children?name/$childrenName/g;
    $line =~ s/\$childrentitle/$childrenTitle/g;
    $line =~ s/\$childrenurls?/$childrenUrls/g;
    $line =~ s/\$children(links?)?/$children/g;
    $line =~ s/\$iconurl/$iconUrl/g;
    $line =~ s/\$icon/$icon/g;
    $line =~ s/\$tags/$tags/g;
    $line =~ s/,/&#44;/g; # hack around MAKETEXT where args are comma separated accidentally
    push @result, $line if $line;
    last if $theLimit && $index >= $theLimit;
  }
  return _expandVariables($theNull) unless @result;
  my $result = $theHeader.join($theSep, @result).$theFooter;
  $result = _expandVariables($result, 'count'=>scalar(@$categories));

  #_writeDebug("result=$result");
  return $result;
}

###############################################################################
sub handleTAGINFO {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  #_writeDebug("called handleTAGINFO(".$params->stringify().")");
  my $theFormat = $params->{format} || '$link';
  my $theSep = $params->{separator};
  my $theHeader = $params->{header} || '';
  my $theFooter = $params->{footer} || '';
  my $thisWeb = $params->{web} || $session->{webName};
  my $thisTopic = $params->{_DEFAULT} || $params->{topic} || $session->{topicName};
  my $theExclude = $params->{exclude} || '';
  my $theInclude = $params->{include} || '';
  my $theLimit = $params->{limit};
  my $theSkip = $params->{skip};

  $theLimit =~ s/[^\d]//g if defined $theLimit;
  $theSkip =~ s/[^\d]//g if defined $theSkip;

  $theSep = ', ' unless defined $theSep;

  ($thisWeb, $thisTopic) = 
    Foswiki::Func::normalizeWebTopicName($thisWeb, $thisTopic);

  $thisWeb =~s/\//./g; # fix subwebbing

  # get tags
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($thisWeb);
  return '' unless $db;
  my $topicObj = $db->fastget($thisTopic);
  return '' unless $topicObj;
  my $form = $topicObj->fastget('form');
  return '' unless $form;
  my $formObj = $topicObj->fastget($form);
  return '' unless $formObj;
  my $tags = $formObj->fastget('Tag');
  return '' unless $tags;
  my @tags = split(/\s*,\s*/, $tags);

  my @result;
  my $context = Foswiki::Func::getContext();
  my $index = 0;
  foreach my $tag (sort @tags) {
    $tag =~ s/^\s+//go;
    $tag =~ s/\s+$//go;
    next if $theExclude && $tag =~ /^($theExclude)$/;
    next if $theInclude && $tag !~ /^($theInclude)$/;
    $index++;
    next if $theSkip && $index <= $theSkip;
    my $line = $theFormat;
    my $url;
    if ($context->{SolrPluginEnabled}) {
      # SMELL: WikiWords are autolinked in parameter position ... wtf
      $url = '<noautolink>%SOLRSCRIPTURL{topic="'.$thisWeb.'.WebSearch" tag="'.$tag.'" separator="&&"}%</noautolink>'; # && to please MAKETEXT :(
    } else {
      $url = Foswiki::Func::getScriptUrlPath($thisWeb, "WebTagCloud", "view", tag=>$tag);
    }
    my $class = $tag;
    $class =~ s/["' ]/_/g;
    $class = "tag_".$class;
    my $link = "<a href='$url' rel='tag' class='\$class'><noautolink>$tag</noautolink></a>";
    $line =~ s/\$index/$index/g;
    $line =~ s/\$url/$url/g;
    $line =~ s/\$link/$link/g;
    $line =~ s/\$class/$class/g;
    $line =~ s/\$name/$tag/g;
    push @result, $line;
    last if $theLimit && $index >= $theLimit;
  }

  my $count = scalar(@tags);
  my $result = $theHeader.join($theSep, @result).$theFooter;
  $result = _expandVariables($result, 
    'web'=>$thisWeb,
    'count'=>$count,
    'index'=>$index,
  );

  #_writeDebug("result='$result'");
  return $result;
}

###############################################################################
# reparent based on the category we are in
# takes the first category in alphabetic order
sub beforeSaveHandler {
  my ($this, $text, $topic, $web, $meta) = @_;

  #_writeDebug("beforeSaveHandler($web, $topic)");

  # remember responsiblePerson
  my ($prevMeta) = Foswiki::Func::readTopic($web, $topic);
  $this->{beforeResponsiblePerson} = _getResponsiblePerson($prevMeta);

  my $doAutoReparent = Foswiki::Func::getPreferencesFlag('CLASSIFICATIONPLUGIN_AUTOREPARENT', $web);

  my $session = $Foswiki::Plugins::SESSION;
  unless ($meta) {
    $meta = Foswiki::Meta->new($session, $web, $topic, $text);
    #_writeDebug("creating a new meta object");
  }

  my %isCatField = ();
  my %isTagField = ();

  my $formName = $meta->getFormName();

  if ($formName) {
    my ($theFormWeb, $theForm) = Foswiki::Func::normalizeWebTopicName($web, $formName);
    my $formDef;
    #_writeDebug("form definition at $theFormWeb, $theForm");
    if (Foswiki::Func::topicExists($theFormWeb, $theForm)) {
      try {
        $formDef = Foswiki::Form->new($session, $theFormWeb, $theForm);
      } catch Foswiki::OopsException with {
        my $e = shift;
        print STDERR "ERROR: can't read form definition $theForm in ClassificationPlugin::Core::beforeSaveHandler\n";
      };
      if ($formDef) {
        foreach my $fieldDef (@{$formDef->getFields()}) {
          #_writeDebug("formDef field $fieldDef->{name} type=$fieldDef->{type}");
          $isCatField{$fieldDef->{name}} = 1 if $fieldDef->{type} eq 'cat';
          $isTagField{$fieldDef->{name}} = 1 if $fieldDef->{type} eq 'tag';
        }
      }
    }
  }

  # There's a serious bug in all Foswiki's that it rewrites all of the
  # topic text - including the meta data - if a topic gets moved to
  # a different web. In an attempt to keep linking WikiWords intact,
  # it rewrites the DataForm, i.e. the names and titles of the
  # formfields. This however breaks mostly every code that relies
  # on the formfields to be named like they where in the beginning.
  # AFAICS, there's no case where renaming the formfield names is
  # desired.
  #
  # What we do here is to loop pre-process the topic being saved right here
  # and remove any leading webname from the those formfields
  # playing a central role in this plugin, TopicType and Category.
  # 
  if (FIXFORMFIELDS) {
    #if (TRACE) {
    #  use Data::Dumper;
    #  $Data::Dumper::Maxdepth = 3;
    #  _writeDebug("BEFORE FIXFORMFIELDS");
    #  _writeDebug(Dumper($meta));
    #}

    foreach my $field ($meta->find('FIELD')) {
      if ($field->{name} =~ /TopicType|Category/) {
        $field->{name} =~ s/^.*[\.\/](.*?)$/$1/;
        $field->{title} =~ s/^.*[\.\/](.*?)$/$1/;
      }
      if ($isCatField{$field->{name}}) {
        #_writeDebug("before, value=$field->{value}");
        $field->{value} =~ s/^top=.*$//; # clean up top= in value definition
        my $item;
        $field->{value} = join(', ', 
            map { 
              $item = $_;
              $item =~ s/^.*[\.\/](.*?)$/$1/; 
              $_ = $item;
            }
            split(/\s*,\s*/, $field->{value})
        ); # remove accidental web part from categories
        #_writeDebug("after, value=$field->{value}");
      }
    }

    #if (TRACE) {
    #  use Data::Dumper;
    #  $Data::Dumper::Maxdepth = 3;
    #  _writeDebug("AFTER FIXFORMFIELDS");
    #  _writeDebug(Dumper($meta));
    #}
  }

  if ($web eq $Foswiki::cfg{TrashWebName}) {
    #_writeDebug("detected a move from $session->{webName} to trash");
    $web = $session->{webName};# operations are on the baseWeb
  }

  # get topic type info
  my $topicType = $meta->get('FIELD', 'TopicType');
  return unless $topicType;
  $topicType = $topicType->{value};

  # fix topic type depending on the form
  #_writeDebug("old TopicType=$topicType");
  my @topicType = split(/\s*,\s*/, $topicType);
  my $index = scalar(@topicType)+3;
  my %newTopicType = map {$_ =~ s/^.*\.//; $_ => $index--} @topicType;

  if ($formName =~ /^Applications[\.\/]ClassificationApp[\.\/]Category$/) {
    $newTopicType{Category} = 2;
    $newTopicType{CategorizedTopic} = 1;
    $newTopicType{WikiTopic} = 0;
  } 
  elsif ($formName =~ /^Applications[\.\/]ClassificationApp[\.\/]CategorizedTopic$/) {
    $newTopicType{CategorizedTopic} = 1;
    $newTopicType{WikiTopic} = 0;
  }
  elsif ($formName =~ /^Applications[\.\/]ClassificationApp[\.\/]TaggedTopic$/) {
    $newTopicType{TaggedTopic} = 1;
    $newTopicType{WikiTopic} = 0;
  }
  elsif ($formName =~ /^Applications[\.\/]ClassificationApp[\.\/]ClassifiedTopic$/) {
    $newTopicType{ClassifiedTopic} = 3;
    $newTopicType{CategorizedTopic} = 2;
    $newTopicType{TaggedTopic} = 1;
    $newTopicType{WikiTopic} = 0;
  }
  if ($formName !~ /^Applications[\.\/]TopicStub$/) {
    delete $newTopicType{TopicStub};
  }

  if (keys %newTopicType) {
    my @newTopicType;
    foreach my $item (sort {$newTopicType{$b} <=> $newTopicType{$a}} keys %newTopicType) {
      push @newTopicType, $item;
    }
    my $newTopicType = join(', ', @newTopicType);
    #_writeDebug("new TopicType=$newTopicType");
    $meta->putKeyed('FIELD', {name =>'TopicType', title=>'TopicType', value=>$newTopicType});
  }

  # get categories of this topic,
  # must get it from current meta data

  return unless $topicType =~ /ClassifiedTopic|CategorizedTopic|Category|TaggedTopic/;

  my $hierarchy = $this->getHierarchy($web);
  my $catFields = $hierarchy->getCatFields(split(/\s*,\s*/,$topicType));

  # get old categories from store 
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  my $topicObj = $db->fastget($topic);
  my %oldCats;
  if (!$topicObj) {
    $this->{purgeMode} = 2; # new topic
  } else {
    my $form = $topicObj->fastget("form");

    if (!$form) {
      $this->{purgeMode} = 2; # new form
    } else {
      $form = $topicObj->fastget($form);
      
      foreach my $field (@$catFields) {
        my $cats = $form->fastget($field);
        next unless $cats;
        foreach my $cat (split(/\s*,\s*/,$cats)) {
          $cat =~ s/^\s+//go;
          $cat =~ s/\s+$//go;
          $oldCats{$cat} = 1;
        }
      }
    }
  }

  # get new categories from meta data
  my %newCats;
  foreach my $field (@$catFields) {
    my $cats = $meta->get('FIELD',$field);
    next unless $cats;

    my $title = $cats->{title};
    $cats = $cats->{value};
    next unless $cats;

    # assigning TopCategory only empties the cat field
    if ($cats eq 'TopCategory') {
      #_writeDebug("found TopCategory assignment");
      $meta->putKeyed('FIELD', {name =>$field, title=>$title, value=>''});
      next;
    }

    foreach my $cat (split(/\s*,\s*/,$cats)) {
      $cat =~ s/^\s+//go;
      $cat =~ s/\s+$//go;
      $newCats{$cat} = 1;
    }
  }

  # set the new parent topic
  if ($doAutoReparent) {
    #_writeDebug("autoreparenting");
    my $newParentCat;
    foreach my $cat (sort keys %newCats) {
      if ($cat ne 'TopCategory') {
        $newParentCat = $cat;
        last;
      }
    }
    my $homeTopicName = $Foswiki::cfg{HomeTopicName};
    $newParentCat = $homeTopicName unless defined $newParentCat;
    #_writeDebug("newParentCat=$newParentCat");
    $meta->remove('TOPICPARENT');
    $meta->putKeyed('TOPICPARENT', {name=>$newParentCat});
  } else {
    #_writeDebug("not autoreparenting");
  }

  # get changed categories
  $this->{changedCats} = ();
  foreach my $cat (keys %oldCats) {
    $this->{changedCats}{$cat} = 1 unless $newCats{$cat};
  }
  foreach my $cat (keys %newCats) {
    $this->{changedCats}{$cat} = 1 unless $oldCats{$cat};
  }

  # add self
  if (!$this->{changedCats}{$topic} && $topicType =~ /\bCategory\b/) {
    $this->{changedCats}{$topic} = 1;
    #_writeDebug("adding self to changedCats");
  }

  # cache invalidation: compute the purgeMode to be executed after save
  $this->{purgeMode} = 1 if $topicType =~ /\bTaggedTopic\b/;
  $this->{purgeMode} = 2 if $topicType =~ /\bCategorizedTopic\b/;
  $this->{purgeMode} = 3 if $topicType =~ /\bClassifiedTopic\b/;
  $this->{purgeMode} = 4 if $topicType =~ /\bCategory\b/;

  # try even harder if it missing the CategorizedTopic TopicType but
  # still uses categories
  if ($this->{purgeMode} < 2) { 
    my $hierarchy = $this->getHierarchy($web); 
    my $catFields = $hierarchy->getCatFields(split(/\s*,\s*/,$topicType));
    if ($catFields && @$catFields) {
      $this->{purgeMode} = ($this->{purgeMode} < 1)?2:3;
    }
  }

  #_writeDebug("purgeMode=$this->{purgeMode}");
  #_writeDebug("changedCats=".join(',', keys %{$this->{changedCats}}));

}

###############################################################################
sub afterSaveHandler {
  #my ($this, $text, $topic, $web, $error, $meta) = @_;
  my $this = shift;
  my $topic = $_[1];
  my $web = $_[2];
  my $meta = $_[4];

  #_writeDebug("afterSaveHandler($web, $topic)");

  my $session = $Foswiki::Plugins::SESSION;
  if ($web eq $Foswiki::cfg{TrashWebName}) {
    #_writeDebug("detected a move from $session->{webName} to trash");
    $web = $session->{webName};# operations are on the baseWeb
  }
  $web =~ s/\//./go;
 
  if ($this->{purgeMode}) {
    #_writeDebug("purging hierarchy $web");
    my $hierarchy = $this->getHierarchy($web);

    # delete the cached html page 
    my $cache = $Foswiki::Plugins::SESSION->{cache} || $Foswiki::Plugins::SESSION->{cache};
    if (defined $cache) {
      foreach my $catName (keys %{$this->{changedCats}}) {
        my $cat = $hierarchy->getCategory($catName);
        next unless $cat;
        if ($cat->{origWeb} eq $web) {
          # category is a topic in this web
          $cache->deletePage($web, $catName);
        } else {
          # category is displayed via the Category topic as it is imported
          $cache->deletePage($web, 'Category');
        }
      }
    }
    #_writeDebug("purging changedCats");

    $hierarchy->purgeCache($this->{purgeMode}, [keys %{$this->{changedCats}}]);
    $this->{purgeMode} = 0; # reset
  }

  # auto-subscribe responsible person
  my $autoSubscribe = Foswiki::Func::getPreferencesValue("AUTOSCUBSCRIBE_RESPONSIBLE_PERSON") || 'on';
  $autoSubscribe = Foswiki::Func::isTrue($autoSubscribe, 1);

  if ($autoSubscribe) {  
    my @unsubscribe = ();
    my @subscribe = ();

    my %before = ();
    foreach my $person (split(/\s*,\s*/, $this->{beforeResponsiblePerson})) {
      $before{$person}++;
    }
    my %after = ();
    my $afterResponsiblePerson = _getResponsiblePerson($meta);
    foreach my $person (split(/\s*,\s*/, $afterResponsiblePerson)) {
      $after{$person}++;
    }
    foreach my $person (keys %before) {
      next if $after{$person};
      push @unsubscribe, $person;
    }
    foreach my $person (keys %after) {
      next if $before{$person};
      push @subscribe, $person;
    }
    
    if (@unsubscribe) {
      #_writeDebug("auto-un-subscribing @unsubscribe");
      Foswiki::Contrib::MailerContrib::changeSubscription($web, $_, $topic, "-") foreach @unsubscribe;
    }
    if (@subscribe) {
      #_writeDebug("auto-subscribing @subscribe");
      Foswiki::Contrib::MailerContrib::changeSubscription($web, $_, $topic) foreach @subscribe;
    }
  }
}

###############################################################################
sub afterRenameHandler {
  my ($this, $fromWeb, $fromTopic, $fromAttachment, $toWeb, $toTopic, $toAttachment) = @_;

  return if $fromAttachment || $toAttachment;

  #_writeDebug("afterRenameHandler($fromWeb, $fromTopic, $toWeb, $toTopic)");

  my ($meta) = Foswiki::Func::readTopic($toWeb, $toTopic);
  my $formName = $meta->getFormName();

  #print STDERR "formName=$formName\n";
  return unless $formName =~ /^Applications[\.\/]ClassificationApp[\.\/]Category$/;

  my $hierarchy = $this->getHierarchy($fromWeb);

  if ($hierarchy) {
    my @changedCats = ($fromTopic);
    push @changedCats, $toTopic if $fromWeb eq $toWeb && $fromTopic ne $toTopic;
    #print STDERR "purge cache for $hierarchy->{web}, affects categories @changedCats\n";
    $hierarchy->purgeCache(4, \@changedCats);
  }

  if ($fromWeb ne $toWeb && $toWeb ne $Foswiki::cfg{TrashWebName}) {
    $hierarchy = $this->getHierarchy($toWeb);

    if ($hierarchy) {
      my @changedCats = ($toTopic);
      $hierarchy->purgeCache(4, \@changedCats);
    }
  } else {
    #_writeDebug("detected rename to trash");
  }
}

################################################################################
sub getCacheFile {
  my ($this, $web, $topic) = @_;

  $web =~ s/^\s+//go;
  $web =~ s/\s+$//go;
  $web =~ s/[\/\.]/_/go;

  my $key = $web;
  $key .= '.'.$topic if defined $topic;

  return Foswiki::Func::getWorkArea("ClassificationPlugin").'/'.$key.'.hierarchy';
}

###############################################################################
sub getModificationTime {
  my ($this, $web, $topic) = @_;

  my $key = $web;
  $key .= '.'.$topic if defined $topic;

  unless ($this->{modTimeStamps}{$key}) {
    my $cacheFile = $this->getCacheFile($web, $topic);
    my @stat = stat($cacheFile);
    $this->{modTimeStamps}{$key} = ($stat[9] || $stat[10] || 1);
  }

  return $this->{modTimeStamps}{$key};
}

###############################################################################
# returns the hierarchy object for a given web; construct a new one if
# not already done
sub getHierarchy {
  my ($this, $web) = @_;

  die "no web defined" unless defined $web;

  unless (Foswiki::Func::webExists($web)) {
    cluck("ERROR: can't get hierarchy for non-existing web '$web'");
    return;
  }

  $web =~ s/\//\./go;
  if (!$this->{loadTimeStamps}{$web} || $this->{loadTimeStamps}{$web} < $this->getModificationTime($web)) {
    #_writeDebug("constructing hierarchy for $web");
    require Foswiki::Plugins::ClassificationPlugin::Hierarchy;
    $this->{hierarchies}{$web} = Foswiki::Plugins::ClassificationPlugin::Hierarchy->new($web);
    $this->{loadTimeStamps}{$web} = time();
    #_writeDebug("DONE constructing hierarchy for $web");
  }

  return $this->{hierarchies}{$web};
}

###############################################################################
# returns the hierarchy object for a given web.topic; construct a new one if
# not already done
sub getHierarchyFromTopic {
  my ($this, $web, $topic) = @_;

  $web =~ s/\//\./go;
  my $key = $web.'.'.$topic;
  my $timeStap = $this->{loadTimeStamps}{$key};

  if (!$timeStap || $timeStap < $this->getModificationTime($web, $topic)) {
    #_writeDebug("constructing hierarchy for $web");
    require Foswiki::Plugins::ClassificationPlugin::Hierarchy;
    $this->{hierarchies}{$key} = Foswiki::Plugins::ClassificationPlugin::Hierarchy->new($web, $topic);
    $this->{loadTimeStamps}{$key} = time();
    #_writeDebug("DONE constructing hierarchy for $web");
  }

  return $this->{hierarchies}{$key};
}

###############################################################################
# returns a hierarchy object for a given bullet list
# not already done
sub getHierarchyFromText {
  my ($this, $text) = @_;

  require Foswiki::Plugins::ClassificationPlugin::Hierarchy;
  return Foswiki::Plugins::ClassificationPlugin::Hierarchy->new(undef, undef, $text, @_);
}


###############################################################################
# get the hierarchy that implements the given category; this traverses all
# webs and loads their hierarchy to see if it exists
sub findHierarchy {
  my ($this, $catName) = @_;

  # try baseweb first
  my $session = $Foswiki::Plugins::SESSION;
  my $hierarchy = $this->getHierarchy($session->{webName});
  my $cat = $hierarchy->getCategory($catName);

  unless ($cat) {
    foreach my $web (Foswiki::Func::getListOfWebs('user')) {
      $hierarchy = $this->getHierarchy($web);
      $cat = $hierarchy->getCategory($catName);
      last if $cat;
    }
  }

  return $hierarchy;
}

###############################################################################
sub renameTag {
  my ($this, $from, $to, $web, $topics) = @_;

  my $hierarchy = $this->getHierarchy($web);
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);

  $topics = [$db->getKeys()] unless $topics;
  my @from = ();

  if (ref($from)) {
    @from = @$from;
  } else {
    @from = split(/\s*,s\*/, $from);
  }

  my $user = Foswiki::Func::getWikiName();
  my $count = 0;
  my $gotAccess;
  foreach my $topic (@$topics) {

    my $tags = $hierarchy->getTagsOfTopic($topic);
    next unless $tags;
    my %tags = map {$_ => 1} @$tags;
    my $found = 0;

    foreach my $from (@from) {
      if ($tags{$from}) {
        $gotAccess = Foswiki::Func::checkAccessPermission('change', $user, undef, $topic, $web)
          unless defined $gotAccess;
        next unless $gotAccess;
        delete $tags{$from};
        $tags{$to} = 1 if $to;
        $found = 1;
      }
    }
    if ($found) {
      my $newTags = join(', ', keys %tags);

      if (TRACE) {
        print STDERR "\n$topic: old=".join(", ", sort @$tags)."\n";
        print STDERR "$topic: new=$newTags\n";
      } 

      my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
      $meta->putKeyed( 'FIELD', { name => 'Tag', title => 'Tag', value =>$newTags});
      #print STDERR "saving $web.$topic\n";
      Foswiki::Func::saveTopic($web, $topic, $meta, $text);
      #print STDERR "...done\n";

      $count++;
    }
  }

  return $count;
}

###############################################################################
sub getIndexFields {
  my ($this, $web, $topic, $meta) = @_;

  $web =~ s/\//./g;
  my $indexFields = $this->{cachedIndexFields}{"$web.$topic"};
  return $indexFields if $indexFields;

  @$indexFields = ();

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless $meta;

  my $session = $Foswiki::Plugins::SESSION;
  my $formName = $meta->getFormName();
  my $formDef;

  try {
    $formDef = Foswiki::Form->new($session, $web, $formName) if $formName;
  } catch Foswiki::OopsException with {
    my $e = shift;
    print STDERR "ERROR: can't read form definition $formName in ClassificationPlugin::Core::getIndexFields\n";
  };

  if ($formDef) {

    my %seenFields = ();
    my %categories;
    my %tags;
    my $hierarchy = $this->getHierarchy($web);
    foreach my $fieldDef (@{$formDef->getFields()}) {
      my $name = $fieldDef->{name};
      my $type = $fieldDef->{type};
      my $field = $meta->get('FIELD', $name);
      my $value = $field->{value} || '';

      next if $seenFields{$name};
      $seenFields{$name} = 1;

       # categories
      if ($type eq 'cat') {
        my %thisCategories = ();
        foreach my $item (split(/\s*,\s*/, $value)) {
          $thisCategories{$item} = 1; # this cat field
          $categories{$item} = 1; # all cat fields
        }

	# first, add categories as is
	foreach my $category (keys %thisCategories) {
	  push @$indexFields, ['field_'.$name.'_flat_lst' => $category];
	}

        if ($hierarchy) {
          # create a category title field
          foreach my $category (keys %thisCategories) {
            my $cat = $hierarchy->getCategory($category);
            next unless $cat;
            push @$indexFields, ['field_'.$name.'_title_lst' => $cat->title];
          }
        

          # then, gather all parent categories for this cat field
          foreach my $category (keys %thisCategories) {
            my $cat = $hierarchy->getCategory($category);
            next unless $cat;
            foreach my $parent ($cat->getAllParents()) {
              $thisCategories{$parent} = 1;
            }
          }
        }

        # create a field specific category facet
	my $fieldName = 'field_'.$name.'_lst'; # Note, there's a field_..._s as well
	foreach my $category (keys %thisCategories) {
	  push @$indexFields, [$fieldName => $category];
	}
      }

      # tags
      elsif ($type eq 'tag') {
        foreach my $item (split(/\s*,\s*/, $value)) {
          $tags{$item} = 1; 
        }
      }
    }

    # gather all parents of all cat fields
    if ($hierarchy) {
      my %seenWebCat = ();
      foreach my $category (keys %categories) {
	my $cat = $hierarchy->getCategory($category);
	next unless $cat;
	foreach my $parent ($cat->getAllParents()) {
	  $categories{$parent} = 1;
	}
        foreach my $breadCrumb ($cat->getAllBreadCrumbs) {
          my $prefix = $web;
          foreach my $component (split(/\./, $breadCrumb)) {
            $prefix .= '.'.$component;
            next if $seenWebCat{$prefix};
            $seenWebCat{$prefix} = 1;
            push @$indexFields, ['webcat' => $prefix];
          }
        }
      }
    }

    # create common fields
    foreach my $category (keys %categories) {
      push @$indexFields, ['category' => $category];
    }
    foreach my $tag (keys %tags) {
      push @$indexFields, ['tag' => $tag];
    }
  }

  $this->{cachedIndexFields}{"$web.$topic"} = $indexFields;
  return $indexFields;
}

###############################################################################
sub indexAttachmentHandler {
  my ($this, $indexer, $doc, $web, $topic, $attachment) = @_;

  my $indexFields = $this->getIndexFields($web, $topic);
  $doc->add_fields(@$indexFields) if $indexFields;
}

###############################################################################
sub getIconOfTopic {
  my ($this, $web, $topic) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  return unless $db;

  my $topicObj = $db->fastget($topic);
  return unless $topicObj;

  my $formName = $topicObj->fastget('form');
  return unless $formName;

  my $form = $topicObj->fastget($formName);
  return unless $form;

  $formName = $form->fastget('name');

  if ($formName =~ /\bTopicStub\b/) {
    my $target = $form->fastget("Target");
    return $this->getIconOfTopic($web, $target);
  }


  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $formName);
  $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  return unless $db;

  $topicObj = $db->fastget($topic);
  return unless $topicObj;

  $form = $topicObj->fastget('form');
  return unless $form;

  $form = $topicObj->fastget($form);
  return unless $form;


  my $icon = $form->fastget("Icon");
  return unless $icon;

  return $icon if defined $icon;
}

###############################################################################
sub indexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  my $indexFields = $this->getIndexFields($web, $topic, $meta);
  $doc->add_fields(@$indexFields) if $indexFields;

  my $icon;

  if ($meta->get('FIELD', 'TopicType')) {
    $icon = $this->getIconOfTopic($web, $topic);
  } 

  if ($icon) {
    my $field = $indexer->getField($doc, "icon");
    $field->value($icon) if $field;
  }
}

###############################################################################
# statics 
###############################################################################
sub _getResponsiblePerson {
  my $meta = shift;

  my $topicType = $meta->get('FIELD', 'TopicType');
  $topicType = $topicType->{value} if $topicType;
  $topicType ||= '';

  return "" unless $topicType =~ /\bCategory\b/;

  my $responsiblePerson = $meta->get('FIELD', "ResponsiblePerson");
  $responsiblePerson = $responsiblePerson->{value} if defined $responsiblePerson;

  return $responsiblePerson || "";
}

###############################################################################
sub _writeDebug {
  print STDERR '- ClassificationPlugin::Core - '.$_[0]."\n" if TRACE;
  #Foswiki::Func::writeDebug('- ClassificationPlugin::Core - '.$_[0]) if TRACE;
}

###############################################################################
sub getTopicTypes {
  my ($this, $web, $topic) = @_;

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  return () unless $db;

  my $topicObj = $db->fastget($topic);
  return () unless $topicObj;

  my $form = $topicObj->fastget("form");
  return () unless $form;

  $form = $topicObj->fastget($form);
  return () unless $form;

  my $topicTypes = $form->fastget('TopicType');
  return () unless $topicTypes;

  return split(/\s*,\s*/, $topicTypes);
}

###############################################################################
sub _expandVariables {
  my ($theFormat, %params) = @_;

  return '' unless $theFormat;

  #_writeDebug("called _expandVariables($theFormat)");

  foreach my $key (keys %params) {
    #die "params{$key} undefined" unless defined($params{$key});
    $theFormat =~ s/\$$key\b/$params{$key}/g;
  }
  $theFormat =~ s/\$percnt/\%/go;
  $theFormat =~ s/\$nop//go;
  $theFormat =~ s/\$n/\n/go;
  $theFormat =~ s/\$t\b/\t/go;
  $theFormat =~ s/\$dollar/\$/go;

  #_writeDebug("result='$theFormat'");

  return $theFormat;
}


1;

