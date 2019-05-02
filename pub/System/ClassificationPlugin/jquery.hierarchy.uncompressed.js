/*
 * jQuery hierarchy plugin 2.00
 *
 * Copyright (c) 2013-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($, window) {

  /***************************************************************************
   * defaults
   */
  var pluginName = "hierarchy",
      defaults = {
        web: undefined,
        topic: undefined,
        url: undefined,
        root: "",
        displayCounts: true,
        mode: "select" /* select, browse or edit */,
        searchButton: ".jqHierarchySearchButton",
        searchField: ".jqHierarchySearchField",
        clearButton: ".jqHierarchyClearButton",
        undoButton: ".jqHierarchyUndoButton",
        refreshButton: ".jqHierarchyRefreshButton",
        inputFieldName: undefined,
        container: undefined,
        multiSelect: true,
        sort: 'index'
      };


  /***************************************************************************
   * constructor 
   */
  function Hierarchy(elem, opts) { 
    var self = this;
    self.elem = $(elem);
    self.opts = $.extend({}, defaults, opts, self.elem.data()); 
    self.init(); 
  } 

  /***************************************************************************
   * initializer 
   */
  Hierarchy.prototype.init = function () {
    var self = this, plugins = ["search"]; 

    self.searchButton = self.elem.find(self.opts.searchButton);
    self.searchField = self.elem.find(self.opts.searchField);
    self.searchButton.click(function() {
      self.searchField.animate({opacity:'toggle'}, 'fast', function() {
        $(this).focus();
      });
      return false;
    });

    self.searchField.bind("keypress", function(event) {
      var $this = $(this), val;
      // track last key pressed
      if(event.keyCode == 13) {
        val = $this.val();
        if (val.length === 0) {
          self.jstree.clear_search();
          $this.hide(); 
        } else {
          $this.effect('highlight');
          self.jstree.search(val);
        }
        event.preventDefault();
        return false;
      }
    });

    self.refreshButton = self.elem.find(self.opts.refreshButton);
    self.refreshButton.click(function() {
      self.refresh();
      return false;
    });

    self.undoButton = self.elem.find(self.opts.undoButton);
    self.undoButton.click(function() {
      self.reset();
      return false;
    });

    self.clearButton = self.elem.find(self.opts.clearButton);
    self.clearButton.click(function() {
      self.clear();
      self.searchField.val("").hide();
      return false;
    });

    if (typeof(self.opts.inputFieldName) !== 'undefined') {
      self.inputField = self.elem.find("input[name='"+self.opts.inputFieldName+"']");
      if (self.inputField.length === 0) {
        self.inputField = undefined;
      }
    }
    if (typeof(self.inputField) === 'undefined') {
      self.inputField = $("<input />").attr({
        type: "hidden",
        name: self.opts.inputFieldName
      }).appendTo(self.container);
    }

    self.origSelection = self.inputField.val();

    if (typeof(self.opts.container) !== 'undefined') {
      self.container = self.elem.find(self.opts.container);
    } else {
      self.container = self.elem;
    }

    if (self.opts.mode === "edit") {
      plugins.push("contextmenu", "dnd");
    }

    // nuke defaults as things get merged otherwise
    $.jstree.defaults.contextmenu.items = {};

    self.treeElem = $("<div />").appendTo(self.container).jstree({
      "plugins": plugins,
      "core": {
        "animation":100,
        "check_callback": true,
        "multiple": true,
        "themes": {
           "url": foswiki.getPubUrl("System", "JSTreeContrib", "themes/minimal/style.css"),
           "name":"minimal", 
           "icons": true
        }, 
        "data": {
          "url": self.opts.url,
          "data": function(node) {
            return {
              "action": "get_children",
              "web": self.opts.web,
              "topic": self.opts.topic,
              "cat": (node.id && node.id !== '#' )? node.id : self.opts.root,
              "select": self.inputField.val(),
              "counts": self.opts.displayCounts,
              "sort": self.opts.sort,
              "t": (new Date()).getTime()
            };
          }
        }
      },
      "search": {
        "show_only_matches": true,
        "show_only_matches_children": true,
        "ajax": {
          "url": self.opts.url,
          "data": function(term) {
            return {
              "action": "search",
              "web": self.opts.web,
              "topic": self.opts.topic,
              "title": term,
              "t": (new Date()).getTime()
            };
          }
        }
      },
      "dnd": {
        "copy": false
      },
      "contextmenu": {
        "select_node": false,
        "items": {
          "create" : {
            "separator_before": false,
            "separator_after": true,
            "icon": self.opts.pubUrlPath+"/"+self.opts.systemWeb+"/FamFamFamSilkIcons/page_white_add.png",
            "label": $.i18n("New"),
            "action": function(obj) { 
              var par = self.jstree.get_node(obj.reference);
              self.jstree.open_node(par, function() {
                var node = self.jstree.create_node(par, { "icon": "fa fa-folder" });
                self.jstree.edit(node);
              });
            }
          },
          "edit" : {
            "separator_before": false,
            "separator_after": false,
            "icon": self.opts.pubUrlPath+"/"+self.opts.systemWeb+"/FamFamFamSilkIcons/pencil.png",
            "label": $.i18n("Edit"),
            "action": function(obj) { 
              var href= obj.reference.data("editUrl");
              if (href) {
                window.location.href = href;
              }
            }
          },
          "view" : {
            "separator_before": false,
            "separator_after": true,
            "label": $.i18n("View"),
            "icon": self.opts.pubUrlPath+"/"+self.opts.systemWeb+"/FamFamFamSilkIcons/eye.png",
            "action": function(obj) { 
              var href= obj.reference.attr("href");
              if (href) {
                window.location.href = href;
              }
            }
          },
          "rename" : {
            "separator_before": false,
            "separator_after": false,
            "label": $.i18n("Rename"),
            "icon": self.opts.pubUrlPath+"/"+self.opts.systemWeb+"/FamFamFamSilkIcons/page_white_go.png",
            "action": function(obj) { 
              var node = self.jstree.get_node(obj.reference),
                  title = obj.reference.data("title");
              self.jstree.edit(node, title, function(node, sts, cancel) {
                if (cancel) {
                  return false;
                }
              });
            }
          },
          "remove" : {
            "separator_before": false,
            "separator_after": false,
            "label": $.i18n("Remove"),
            "icon": self.opts.pubUrlPath+"/"+self.opts.systemWeb+"/FamFamFamSilkIcons/bin.png",
            "action": function(obj) { 
              self.confirm({
                message: "<div class='foswikiCenter'>" + 
                  $.i18n("Are you sure that you want to delete<br /><b>%title%</b>?", {
                    title: obj.reference.data("title")
                  }) + "</div>",
                okayText: $.i18n("Yes, delete it."),
                okayIcon: "ui-icon-trash",
                cancelText: $.i18n("No, thanks.")
              }).then(function() {
                var node = self.jstree.get_node(obj.reference);
                self.jstree.delete_node(node);
              });
            }
          }
        }
      }
    });
    self.jstree = self.treeElem.jstree(true);

    if (self.opts.mode === "edit") {

      /* moving a node */
      self.treeElem.bind("move_node.jstree", function(e, data) {
        var parNode, parTitle, nodeTitle;

        if (self._ignore_move_node) {
          return;
        }

        if (data.parent === '#') {
          parTitle = "TOP";
        } else {
          parNode = self.jstree.get_node(data.parent);
          parTitle = parNode.a_attr["data-title"];
        }

        nodeTitle = data.node.a_attr["data-title"];

        self.confirm({
          message:"<div class='foswikiCenter'>" + 
                  $.i18n("Are you sure that you want to move <br /><b>%cat%</b><br/>to<br /><b>%to%</b>?", {
                    cat: nodeTitle,
                    to: parTitle
                  }) + 
                  "</div>",
          okayText: $.i18n("Yes, move it."),
          cancelText: $.i18n("No, thanks.")
        }).then(function() {
          self.moveNode(data.node, data.parent, data.position, data.old_parent);
        }, function() {
          self._ignore_move_node = true;
          self.jstree.move_node(data.node, data.old_parent, data.old_position);
          self._ignore_move_node = false;
        });
      })

      /* renaming a node */
      .bind("rename_node.jstree", function(ev, data) {
        if (data.node.a_attr.href === '#') {
          self.createNode(data.node);
        } else if (data.text !== data.old) {
          self.renameNode(data.node, data.text);
        }
      })

      /* removing a node */
      .bind("delete_node.jstree", function (e, obj) {
        $.ajax({
          type: 'POST',
          url: self.opts.url,
          data : { 
            "action" : "remove_node", 
            "web": self.opts.web,
            "topic": self.opts.topic,
            "cat": obj.node.id,
            "t": (new Date()).getTime()
          }, 
          error: function() {
            // error
          },
          success: function() {
            self.removeVal(this.id);
          },
          complete: function(xhr) {
            var response = $.parseJSON(xhr.responseText);
            //console.log(response);
            $.pnotify({
              type: response.type,
              title: response.title,
              text: response.message
            });
          }
        });
      });
    } // end if edit


    self.treeElem.bind("loaded.jstree", function() {
      self.reset();
    }).bind("select_node.jstree", function(e, obj) {
      var node = obj.node, 
          id = node.id, 
          href = node.a_attr.href,
          baseTopic = foswiki.getPreference("TOPIC");

      if (self.opts.mode === 'select') {
        if (id === baseTopic) {
          /*
          $.pnotify({
            type: "error",
            text: $.i18n("Don't select yourself."),
            delay: 2000
          });*/
          self.jstree.deselect_node(id);
        } else {
          self.addVal(id);
        }
      } 

      if (self.opts.mode === 'browse') {
        if (obj.event.ctrlKey) {
          window.open(href);
        } else {
          window.location.href = href;
        }
        e.preventDefault();
        return false; 
      }

    }).bind("deselect_node.jstree", function(e, obj) {
      var node = obj.node, id = node.id;
      self.removeVal(id);
    });
  }; 

  /***************************************************************************
   * get selected categories 
   */
  Hierarchy.prototype.getSelection = function() {
    var self = this, vals = [];

    $.each(self.jstree.get_selected(), function(i, item) {
      if ( $.inArray(item, vals) < 0) {
        vals.push(item);
      }
    });

    return vals;
  };


  /***************************************************************************
   * set selected categories 
   */
  Hierarchy.prototype.setSelection = function(vals) {
    var self = this;

    if (typeof(vals) === 'string') {
      vals = vals.split(/\s*,\s*/);
    } else {
      vals = vals || [];
    }

    self.inputField.val(vals.sort().join(", ")).trigger("change");
    self.jstree.select_node(vals);

    return vals;
  };

  /***************************************************************************
   * add value to list stored in input field 
   */
  Hierarchy.prototype.addVal = function(val) {
    var self = this,
        vals = self.getSelection();

    if ($.inArray(val, vals) < 0) {
      vals.push(val);
    }

    return self.setSelection(vals);
  };

  /***************************************************************************
   * remove value from input field storing a list
   */
  Hierarchy.prototype.removeVal = function(val) {
    var self = this,
        vals = self.getSelection(),
        newVals = [], i, value;

    for (i = 0; i < vals.length; i++)  {
      value = vals[i];
      if (!value) {
        continue;
      }
      if (value != val) {
        newVals.push(value);
      }
    }

    return self.setSelection(newVals);
  };

  /***************************************************************************
   * rename a node's title
   */
  Hierarchy.prototype.renameNode = function(node, title) {
    var self = this;

    return $.ajax({
      type: "POST",
      dataType: "json",
      url: self.opts.url,
      data: { 
        "action" : "rename_node", 
        "web": self.opts.web,
        "topic": self.opts.topic,
        "cat" : node.id,
        "title": title,
        "t": (new Date()).getTime()
      },
      error: function() {
        //$.jstree.rollback(data.rlbk);
      },
      complete: function(xhr) {
        var response = $.parseJSON(xhr.responseText);
        //console.log(response);
        $.pnotify({
          type: response.type,
          title: response.title,
          text: response.message
        });
      }
    });
  };

  /***************************************************************************
   * move a node to a new parent category
   */
  Hierarchy.prototype.moveNode = function(node, par, pos, old) {
    var self = this,
        obj = self.jstree.get_node(node.id, true),
        next = self.jstree.get_next_dom(obj, true),
        prev = self.jstree.get_prev_dom(obj, true);

    if (par === "#") {
      par = "TopCategory";
    }

    if (old === "#") {
      old = "TopCategory";
    }

    $.ajax({
      type: "POST",
      dataType: "json",
      url: self.opts.url,
      data: { 
        "action": "move_node", 
        "web": self.opts.web,
        "topic": self.opts.topic,
        "cat": node.id,
        "parent": par,
        "oldParent": old,
/*
        "next": next?next.attr("id"):undefined,
        "prev": prev?prev.attr("id"):undefined,
*/
        "t": (new Date()).getTime()
      },
      error: function() {
        //$.jstree.rollback(data.rlbk);
      },
      success: function (response) {
        self.jstree.refresh();
      },
      complete: function(xhr) {
        var response = $.parseJSON(xhr.responseText);
        //console.log(response);
        $.pnotify({
          type: response.type,
          title: response.title,
          text: response.message
        });
      }
    });
  };

  /***************************************************************************
   * create a node
   */
  Hierarchy.prototype.createNode = function(node) {
    var self = this,
        par = node.parent,
        title = node.text,
        id = $.wikiword.wikify(title, {
          suffix: "Category",
          transliterate: true
        });
        
    $.ajax({
      type: "POST",
      dataType: "json",
      url: self.opts.url,
      data: {
        "action" : "create_node", 
        "web": self.opts.web,
        "topic": self.opts.topic,
        "cat": id,
        "title": title,
        "parent": par,
        "t": (new Date()).getTime()
        //, "position": pos
      }, 
      error: function() {
        //$.jstree.rollback(data.rlbk); 
      },
      success: function(response) {
        //$(data.rslt.obj).data("name", response.id).data("title", title).addClass(response.id);
        self.jstree.refresh();
      },
      complete: function(xhr) {
        var response = $.parseJSON(xhr.responseText);
        //console.log(response);
        $.pnotify({
          type: response.type,
          title: response.title,
          text: response.message
        });
      }
    });
  };

  /***************************************************************************
   * refresh the hierarchy cache on the backend
   */
  Hierarchy.prototype.refresh = function() {
    var self = this;

    $.ajax({
      type: "POST",
      dataType: "json",
      url: self.opts.url,
      data: { 
        "action" : "refresh", 
        "web": self.opts.web,
        "topic": self.opts.topic,
        "t": (new Date()).getTime()
      },
      beforeSend: function() {
        $.blockUI({message:"<h1>"+$.i18n("Refreshing ...")+"</h1>"});
      },
      complete: function(xhr) {
        var response = $.parseJSON(xhr.responseText);
        $.unblockUI();
        //console.log(response);
        $.pnotify({
          type: response.type,
          title: response.title,
          text: response.message
        });
        self.jstree.refresh();
        self.reset();
      }
    });
  };

  /***************************************************************************
   * clear any selection
   */
  Hierarchy.prototype.clear = function() {
    var self = this;
    self.inputField.val("").trigger("change");
    self.jstree.deselect_all();
  };

  /***************************************************************************
   * reset to original selection
   */
  Hierarchy.prototype.reset = function() {
    var self = this;
    self.clear();
    self.setSelection(self.origSelection);
  };


  /***************************************************************************
   * confirm dialog
   */
  Hierarchy.prototype.confirm = function(opts) {
    var defaults = {
      message: "",
      title: "Confirmation required",
      okayText: $.i18n("Ok"),
      okayIcon: "ui-icon-check",
      cancelText: $.i18n("Cancel"),
      cancelIcon: "ui-icon-cancel",
      width: 'auto'
    };

    if (typeof(opts) === 'string') {
      opts = {
        message: opts
      };
    }
    opts = $.extend({}, defaults, opts);

    return $.Deferred(function(dfd) {
      $("<div></div>").dialog({
        buttons: [{
          text: opts.okayText,
          icon: opts.okayIcon,
          click: function() {
            $(this).dialog("close");
            dfd.resolve();
            return true;
          }
        }, {
          text: opts.cancelText,
          icon: opts.cancelIcon,
          click: function() {
            $(this).dialog("close");
            dfd.reject();
            return false;
          }
        }],
        close: function(event, ui) {
          $(this).remove();
        },
        show: 'fade',
        draggable: false,
        resizable: false,
        title: opts.title,
        modal: true,
        width: opts.width
      }).html(opts.message);
    }).promise();
  };

  /***************************************************************************
   * add to jquery 
   */
  $.fn[pluginName] = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, pluginName)) { 
        $.data(this, pluginName, new Hierarchy(this, opts)); 
      } 
    }); 
  };

  /***************************************************************************
   * dom initializer
   */
  $(function() {
    defaults.pubUrlPath = foswiki.getPreference("PUBURLPATH");
    defaults.systemWeb = foswiki.getPreference("SYSTEMWEB");
    defaults.web = foswiki.getPreference("WEB");
    defaults.topic = defaults.web+'.'+foswiki.getPreference("TOPIC");
    defaults.url = foswiki.getScriptUrl("rest", "ClassificationPlugin", "jsTreeConnector");

    /* enable class-based instantiation  */
    $(".jqHierarchy").livequery(function() {
      $(this).addClass("clearfix").hierarchy();
    });
  });

})(jQuery, window);
