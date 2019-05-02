/*
 * jQuery CatSelector plugin 2.01
 *
 * Copyright (c) 2008-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
jQuery(function($) {

  /***************************************************************************
   * plugin constructor 
   */
  $.fn.catSelector = function(opts) {
    new $.CatSelector(this, opts);
  };

  /***************************************************************************
   * plugin defaults
   */
  var defaults = {
    fieldname: 'Category',
    root: 'TopCategory',
    hidenull: 'off',
    nrleafs: '',
    nrtopics: '',
    format:'editor',
    data: {
      name:'DBCALL',
      param:'Applications.ClassificationApp.RenderHierarchyAsJSON',
      depth:2
    },
    nothingFound: 'Nothing found',
    minSearch: 2
  };

  /***************************************************************************
   * CatSelector class
   */
  $.CatSelector = function(container, opts) {
    var self = this;
    self.container = $(container);
    self.opts = $.extend({}, defaults, opts);

    // gather interface elements
    self.inputField = self.container.find(".clsCategoryField");
    self.browserElem = self.container.find(".clsBrowser");
    self.filterField = self.container.find(".clsFilterField");
    self.filterButton = self.container.find(".clsFilterButton");
    self.clearButton = self.container.find(".clsClearButton");
    self.undoButton = self.container.find(".clsUndoButton");

    self.origValues = self.inputField.val() || '';
    self.origSearch = self.filterField.val() || '';

    self.filterButton.click(function() {
      self.filterField.animate({opacity:'toggle'}, 'fast', function() {
        $(this).focus();
      });
      return false;
    });

    self.clearButton.click(function() {
      self.inputField.val('');
      self.filterField.val('');
      self.load();
      return false;
    });

    self.undoButton.click(function() {
      self.inputField.val(self.origValues);
      self.filterField.val(self.origSearch);
      self.load();
      return false;
    });

    self.filterField.bind("keypress", function(event) {
      // track last key pressed
      if(event.keyCode == 13) {
        var val = self.filterField.val();
        if (val.length == 0 || val.length > self.opts.minSearch) {
          self.load();
        } else {
          self.filterField.effect('highlight');
        }
        event.preventDefault();
        return false;
      }
    });

    self.load();
  };

  /***************************************************************************
   * loads the treeview
   */
  $.CatSelector.prototype.load = function() {
    var self = this;
    $.log("CATSELECTOR: load");

    // update url for treeview
    var url = self.opts.url;
    var postData = $.extend({}, self.opts.data, {
      'web':self.opts.web,
      'topic':self.opts.topic,
      'fieldname':self.opts.fieldname,
      'format':self.opts.format,
      'nrleafs':self.opts.nrleafs,
      'nrtopics':self.opts.nrtopics,
      'hidenull':self.opts.hidenull,
      'exclude':self.opts.exclude
    });
    var values = self.inputField.val() || '';
    if (values) {
      postData.open = values;
    }
    var filter = self.filterField.val();
    if (filter) {
      postData.search = filter;
    }
    var treeviewOpts =  {
      animate: 'fast',
      unique: false,
      root: self.opts.root,
      url: url,
      data: postData
    }
    $.log("CATSELECTOR: new treeview url="+treeviewOpts.url);

    self.browserElem.empty().append("<span class='jqAjaxLoader'>&nbsp;</span>");
    self.treeViewElem = $("<ul></ul>").appendTo(self.browserElem);
    self.treeViewElem.treeview(treeviewOpts);
    self.firstLoad = true;

    /* listen to the treeview's add event; triggered when the tree is extended */
    self.treeViewElem.bind("add", function(event, elem) {
        $.log("CATSELECTOR: triggered add");
        if (self.firstLoad) {
          $.log("CATSELECTOR: 1rst load");
          self.firstLoad = false;
          self.browserElem.find(">.jqAjaxLoader").remove();
          if (self.treeViewElem.find("li").length == 0) {
            self.browserElem.append("<span class='foswikiAlert'>"+self.opts.nothingFound+"</span>");
          }
        }
        $(elem).find('li.open > ul > li.closed').removeClass('closed').addClass('open');

    	/* filter out expandables that have reached the max depth */
	$(elem).find(".clsCategory").each(function() {
	  var $cat = $(this), opts = $.extend({}, $cat.metadata());
          if (opts.depth > self.opts.depth) {
            var $li = $cat.parent().parent();
	    $li.removeClass("hasChildren expandable collapsable")
            if ($li.is(".lastExpandable")) {
	      $li.removeClass("lastExpandable").addClass("last");
            }
            $li.children(".hitarea, ul").remove();
	    //console.log("reached max depth at ", $li, "class=",$li.attr("class"));
          }
        });

        // hilight current values
        var values = $.trim(self.inputField.val() || '');
        values = values.split(/\s*,\s*/);
        var len = values.length;
        for (var i = 0; i < len; i++) {
          var val = values[i];
          if (val) {
            self.treeViewElem.find("."+val).addClass("current");
          }
        }

        // hilight search matches
        var filter = self.filterField.val();
        if (filter) {
          self.highlightText(elem[0], filter);
        }

        // install click handler for categories in the tree view
        $("a.clsCategory:not(.clsInitedCategory)", self.treeViewElem).each(function() {
          var $this = $(this);
          $this.addClass("clsInitedCategory");
          $this.click(function(e) {
            //e.stopPropagation();
            var val = $this.attr('value');
            var title = $this.attr('title') || val;
            if ($this.is(".current")) {
              $.log("CATSELECTOR: deselecting val="+val);
              self.treeViewElem.find("."+val).removeClass("current");
              self.removeVal(val);
            } else {
              $.log("CATSELECTOR: selecting val="+val);
              self.treeViewElem.find("."+val).addClass("current");
              self.addVal(val);
            }
            if (self.opts.onclick !== undefined) {
              self.opts.onclick.call(this, this, self);
            }
            return false;
          });
        });
    });

    if(self.filterField.val() != '') {
      self.filterField.show().focus();
    }
  };

  /***************************************************************************
   * add value to list stored in input field 
   */
  $.CatSelector.prototype.addVal = function(val) {
    var self = this;

    $.log("CATSELECTOR: adding value "+val);
    var values = $.trim(self.inputField.val() || '');
    values = values.split(/\s*,\s*/);
    var newValues = [];
    for (var i = 0; i < values.length; i++)  {
      var value = values[i];
      if (!value)
        continue;
      if (value != val) {
        newValues.push(value);
      }
    }
    newValues.push(val);
    self.inputField.val(newValues.sort().join(', '));
  };

  /***************************************************************************
   * remove value from input field storing a list
   */
  $.CatSelector.prototype.removeVal = function(val) {
    var self = this;

    var values = $.trim(self.inputField.val() || '');
    values = values.split(/\s*,\s*/);
    var newValues = [];
    for (var i = 0; i < values.length; i++)  {
      var value = values[i];
      if (!value)
        continue;
      if (value != val) {
        newValues.push(value);
      }
    }
    self.inputField.val(newValues.sort().join(', '));
  };

  /***************************************************************************
   * find text and hilight it
   */
  $.CatSelector.prototype.highlightText = function(node, text) {
    var self = this;

    text = text.toUpperCase();

    if (node.nodeType == 3) {
      var position = node.data.toUpperCase().indexOf(text);
      if (position >= 0) {
        var spannode = document.createElement('span');
        spannode.className = 'clsHilight';
        var middlebit = node.splitText(position);
        var endbit = middlebit.splitText(text.length);
        var middleclone = middlebit.cloneNode(true);
        spannode.appendChild(middleclone);
        middlebit.parentNode.replaceChild(spannode, middlebit);
        return 1;
      } 
    } else {
      if (node.nodeType == 1 && node.childNodes && !(/(script|style)/i.test(node.tagName))) {
        for (var i = 0; i < node.childNodes.length; ++i) {
          i += self.highlightText(node.childNodes[i], text);
        }
      }
    }
    return 0;
  }
 
  /***************************************************************************
   * initialisation
   */
  $(function() {
    defaults.web = foswiki.getPreference("WEB");
    defaults.topic = defaults.web+'.'+foswiki.getPreference("TOPIC");
    defaults.url = foswiki.getPreference("SCRIPTURL")+"/rest/RenderPlugin/tag";

    $(".clsCatSelector:not(.clsInitedCatSelector)").livequery(function() {
      var $this = $(this);
      $this.addClass("clsInitedCatSelector");
      var opts = $.extend({}, $this.metadata());
      $this.catSelector(opts);
    });
  });

});
