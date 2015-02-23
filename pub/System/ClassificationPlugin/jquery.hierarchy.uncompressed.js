/*
 * jQuery hierarchy plugin 0.10
 *
 * Copyright (c) 2013-2015 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */

(function($, window, document) {
"use strict";

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
        mode: "select" /* browse, select, edit */,
        searchButton: ".jqHierarchySearchButton",
        searchField: ".jqHierarchySearchField",
        clearButton: ".jqHierarchyClearButton",
        resetButton: ".jqHierarchyResetButton",
        refreshButton: ".jqHierarchyRefreshButton",
        inputFieldName: undefined,
        container: undefined,
        multiSelect: true,
        sort: 'index'
      };

  /***************************************************************************
   * multi word search method for jstree (
   */
  $.expr[':'].jstree_contains_all = function(a,i,m) {
    var word, words = [],
        searchFor = m[3].toLowerCase().replace(/^\s+/g,'').replace(/\s+$/g,''),
        j;

    if (searchFor.indexOf(' ') >= 0) {
      words = searchFor.split(' ');
    } else {
      words = [searchFor];
    }

    for (j = 0; j < words.length; j++) {
      word = words[j];
      if ((a.textContent || a.innerText || "").toLowerCase().indexOf(word) == -1) {
        return false;
      }
    }

    return true;
  };

  $.expr[':'].jstree_contains_any = function(a,i,m) {
    var word, words = [],
        searchFor = m[3].toLowerCase().replace(/^\s+/g,'').replace(/\s+$/g,''),
        j;

    if (searchFor.indexOf(' ') >= 0) {
      words = searchFor.split(' ');
    } else {
      words = [searchFor];
    }

    for (j = 0; j < words.length; j++) {
      word = words[j];
      if ((a.textContent || a.innerText || "").toLowerCase().indexOf(word) >= 0) {
        return true;
      }
    }

    return false;
  };

  /***************************************************************************
   * jstree plugin to display counts in nodes
   */
  $.jstree.plugin("counts", { 
    _fn: {
      get_text: function(obj) {
        var s, result;

        obj = this._get_node(obj);
        if (!obj.length) { 
          return false; 
        }
        obj = obj.children("a:eq(0)");

        s = this._get_settings().core.html_titles;
        if (s) {
          obj = obj.clone();
          obj.children("ins,span").remove();
          return obj.html();
        } else {
          obj = obj.contents().filter(function() { return this.nodeType == 3; })[0];
          return obj.nodeValue;
        }
      },
      set_text: function (obj, val) {
        var tmp, count;

        if (typeof(val) === 'undefined') {
          val = obj.data("name");
        }

        obj = this._get_node(obj);
        count = obj.data("nrTopics");
        
        if (count) {
          val += "<span class='jstree-count'>("+count+")</span>";
        }

        if(!obj.length) { 
          return false; 
        }
        obj = obj.children("a:eq(0)");

        if(this._get_settings().core.html_titles) {
          tmp = obj.children("INS").clone();
          obj.html(val).prepend(tmp);
          this.__callback({ "obj" : obj, "name" : val });
          return true;
        } else {
          obj = obj.contents().filter(function() { return this.nodeType == 3; })[0];
          this.__callback({ "obj" : obj, "name" : val });
          return (obj.nodeValue = val);
        }
      }
    }    
  });

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
    var self = this, plugins = ["themes", "json_data", "search", "counts"];

    if (typeof(self.opts.container) !== 'undefined') {
      self.container = self.elem.find(self.opts.container);
    } else {
      self.container = self.elem;
    }

    if (self.opts.mode === "select") {
      plugins.push("ui");
    }

    if (self.opts.mode === "edit") {
      plugins.push("ui", "contextmenu", "crrm", "dnd");
    }

    // nuke defaults as things get merged otherwise
    $.jstree.defaults.contextmenu.items = {};

    self.worker = $("<div />").appendTo(self.container).jstree({
      "plugins": plugins,
      "themes": {
         "theme":"minimal", 
         "icons": true
      }, 
      "ui": {
         "select_limit":self.opts.multiSelect?-1:1,
         "selected_parent_close":false
      },
      "core": {
        "animation":100,
        "html_titles": true
      },
      "json_data": {
        "ajax": {
          "url": self.opts.url,
          "data": function(node) {
            return {
              "action": "get_children",
              "web": self.opts.web,
              "topic": self.opts.topic,
              "cat": node.attr ? node.data("name") : self.opts.root,
              "select": self.inputField.val(),
              "counts": self.opts.displayCounts,
              "sort": self.opts.sort,
              "t": (new Date()).getTime()
            };
          },
          "success": function(data) {
            window.setTimeout(function() {
              self.setSelection(self.inputField.val().split(/\s*,\s*/));
            });
          }
        }
      },
      "search": {
        "search_method": "jstree_contains_all",
        //"show_only_matches": true,
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
      "contextmenu": {
        "items": {
          "create" : {
            "separator_before": false,
            "separator_after": true,
            "icon": defaults.pubUrlPath+"/"+defaults.systemWeb+"/FamFamFamSilkIcons/page_white_add.png",
            "label": "New",
            "action": function(obj) { 
              this.create(obj); 
            }
          },
          "edit" : {
            "separator_before": false,
            "separator_after": false,
            "icon": defaults.pubUrlPath+"/"+defaults.systemWeb+"/FamFamFamSilkIcons/pencil.png",
            "label": "Edit",
            "action": function(obj) { 
              var href= $(obj).data("editUrl");
              if (href) {
                window.location.href = href;
              }
            }
          },
          "view" : {
            "separator_before": false,
            "separator_after": true,
            "label": "View",
            "icon": defaults.pubUrlPath+"/"+defaults.systemWeb+"/FamFamFamSilkIcons/eye.png",
            "action": function(obj) { 
              var href= $(obj.context).attr("href");
              if (href) {
                window.location.href = href;
              }
            }
          },
          "rename" : {
            "separator_before": false,
            "separator_after": false,
            "label": "Rename",
            "icon": defaults.pubUrlPath+"/"+defaults.systemWeb+"/FamFamFamSilkIcons/page_white_go.png",
            "action": function(obj) { 
              this.rename(obj); 
            }
          },
          "remove" : {
            "separator_before": false,
            "separator_after": false,
            "label": "Delete",
            "icon": defaults.pubUrlPath+"/"+defaults.systemWeb+"/FamFamFamSilkIcons/bin.png",
            "action": function(obj) { 
              if(this.is_selected(obj)) { 
                this.remove(); 
              } else { 
                this.remove(obj); 
              } 
            }
          }
        }
      }
    });

    if (self.opts.mode === "edit") {

      /* moving a node */
      self.worker.bind("move_node.jstree", function(e, data) {
        var node = $(data.rslt.o),
            catName = node.data("name"),
            catTitle = node.data("title"),
            newParent = data.rslt.np.data("name"),
            newParentTitle = data.rslt.np.data("title"),
            oldParent = data.rslt.op.data("name"),
            oldParentTitle = data.rslt.op.data("title"),
            nextCat = node.next().data("name"),
            prevCat = node.prev().data("name"),
            position = data.rslt.p,
            copy = data.rslt.cy ? 1 : 0;

        //console.log("data=",data);
        //console.log("catName=",catName,"newParent=",newParent,"oldParent=",oldParent,"nextCat=",nextCat,"prevCat=",prevCat,"position=",position,"copy=",copy);

        $.vakata.context.hide();

        self.confirm({
            message:"<div class='foswikiCenter'>Are you sure that you want to move <br />" +
                    "<b>"+catTitle+"</b><br/>" +
                    "to<br />" +
                    "<b>"+(newParent?newParentTitle:'TOP')+"</b>?</div>",
            okayText: "Yes, move it.",
            cancelText: "No, thanks."
          }).then(function() {
          data.rslt.o.each(function(i) {
            $.ajax({
              async: false,
              type: "POST",
              dataType: "json",
              url: self.opts.url,
              data: { 
                "action": "move_node", 
                "web": self.opts.web,
                "topic": self.opts.topic,
                "cat": catName,
                "parent":newParent,
                "oldParent":oldParent,
                "next": nextCat,
                "prev": prevCat,
                "copy": copy,
                "t": (new Date()).getTime()
              },
              error: function() {
                $.jstree.rollback(data.rlbk);
              },
              success: function (response) {
                $(data.rslt.oc).data("name", response.id).addClass(response.id);
                if(copy && $(data.rslt.oc).children("UL").length) {
                  data.inst.refresh(data.inst._get_parent(data.rslt.oc));
                }
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
        }, function() {
          $.jstree.rollback(data.rlbk);
        });
      })

      /* renaming a node */
      .bind("rename.jstree", function (e, data) {
        var catName = data.rslt.obj.data("name"),
            newTitle = data.rslt.new_name,
            oldTitle = data.rslt.old_name;

        if (typeof(newTitle) === 'undefined' || newTitle === '') {
          newTitle = catName;
        }

        if (newTitle === oldTitle) {
          return;
        }

        //console.log("renaming '"+catName+"' to '"+newTitle+"'");
        //console.log("rslt=",data.rslt);

        $.ajax({
          async: false,
          type: "POST",
          dataType: "json",
          url: self.opts.url,
          data: { 
            "action" : "rename_node", 
            "web": self.opts.web,
            "topic": self.opts.topic,
            "cat" : catName,
            "title": newTitle,
            "t": (new Date()).getTime()
          },
          error: function() {
            $.jstree.rollback(data.rlbk);
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
      })
      .delegate("a", "dblclick", function(event, data) {
        var catName = $(event.target).parent().data("name");
        self.worker.jstree("rename", "."+catName);
        return false;
      })

      /* creating a node */
      .bind("create.jstree", function (e, data) {
        var parentName = data.rslt.parent.data("name"),
            title = data.rslt.name,
            pos = data.rslt.position,
            catName = title;

        if (!title.match(/Category$/)) {
          catName += "Category";
        }

        catName = $.wikiword.wikify(catName);

        //console.log("creating '"+catName+"', title='"+title+"' in '"+parentName+"'");
        //console.log("rslt=",data.rslt);

        $.ajax({
          async: false,
          type: "POST",
          dataType: "json",
          url: self.opts.url,
          data: {
            "action" : "create_node", 
            "web": self.opts.web,
            "topic": self.opts.topic,
            "cat": catName,
            "title": title,
            "parent": parentName,
            "t": (new Date()).getTime()
            //, "position": pos
          }, 
          error: function() {
            $.jstree.rollback(data.rlbk);
          },
          success: function(response) {
            $(data.rslt.obj).data("name", response.id).data("title", title).addClass(response.id);
            //self.worker.jstree("refresh", -1);
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
      })

      /* removing a node */
      .bind("remove.jstree", function (e, data) {
        var catName = data.rslt.obj.data("name"),
            catTitle = data.rslt.obj.data("title");

        $.vakata.context.hide();

        self.confirm({
          message: "<div class='foswikiCenter'>Are you sure that you want to delete<br /><b>"+catTitle+"</b>?",
          okayText: "Yes, delete it.",
          okayIcon: "ui-icon-trash",
          cancelText: "No, thanks."
        }).then(function() {
          data.rslt.obj.each(function () {
            $.ajax({
              async : false,
              type: 'POST',
              url: self.opts.url,
              data : { 
                "action" : "remove_node", 
                "web": self.opts.web,
                "topic": self.opts.topic,
                "cat": catName,
                "t": (new Date()).getTime()
              }, 
              error: function() {
                $.jstree.rollback(data.rlbk);
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
        }, function() {
          $.jstree.rollback(data.rlbk);
        });
      });
    } // end if edit

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
          self.worker.jstree("close_all", -1, 0);
          self.worker.jstree("refresh", -1);
          $this.hide(); 
        } else {
          $this.effect('highlight');
          self.worker.jstree("close_all", -1, 0);
          self.worker.jstree("search", val);
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

    self.resetButton = self.elem.find(self.opts.resetButton);
    self.resetButton.click(function() {
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

    self.worker.bind("select_node.jstree", function(event, data) {
      var name = data.rslt.obj.data("name");

      //console.log("select '"+name+"'");

      self.addVal(name);
      self.elem.find("."+name).each(function() {
        var $this = $(this);
        if(!$this.data("_seen")) {
          $this.data("_seen", true);
          self.worker.jstree("select_node", this);
        }
      }).each(function() {
        $(this).data("_seen", false);
      });
    }).bind("deselect_node.jstree", function(event, data) {
      var name = data.rslt.obj.data("name");

      //console.log("deselect '"+name+"'");

      self.removeVal(name);
      self.elem.find("."+name).each(function() {
        var $this = $(this);
        if(!$this.data("_seen")) {
          $this.data("_seen", true);
          self.worker.jstree("deselect_node", this);
        }
      }).each(function() {
        $(this).data("_seen", false);
      });
    });
  }; 

  /***************************************************************************
   * get selected categories 
   */
  Hierarchy.prototype.getSelection = function() {
    var self = this, selection = [];

    $.each(self.worker.jstree("get_selected"), function(i, item) {
      var name = $(item).data("name");
      if ($.inArray(name, selection) < 0) {
        selection.push(name);
      }
    });

    return selection;
  };


  /***************************************************************************
   * set selected categories 
   */
  Hierarchy.prototype.setSelection = function(vals) {
    var self = this;

    $.each(vals, function(i, item) {
      if (item !== '') {
        self.elem.find("."+item).each(function() {
          self.worker.jstree("select_node", this);
        });
      }
    });
  };

  /***************************************************************************
   * add value to list stored in input field 
   */
  Hierarchy.prototype.addVal = function(val) {
    var self = this,
        newValues = self.removeVal(val);

    newValues.push(val);
    self.inputField.val(newValues.sort().join(', '));

    return newValues;
  };

  /***************************************************************************
   * remove value from input field storing a list
   */
  Hierarchy.prototype.removeVal = function(val) {
    var self = this,
        values = $.trim(self.inputField.val() || ''),
        newValues, i, value;

    values = values.split(/\s*,\s*/);
    newValues = [];
    for (i = 0; i < values.length; i++)  {
      value = values[i];
      if (!value) {
        continue;
      }
      if (value != val) {
        newValues.push(value);
      }
    }

    self.inputField.val(newValues.sort().join(', '));

    return newValues;
  };

  /***************************************************************************
   * reset to original selection
   */
  Hierarchy.prototype.reset = function() {
    var self = this;
    self.inputField.val(self.origSelection);
    self.worker.jstree("refresh", -1);
  };

  /***************************************************************************
   * refresh the hierarchy cache on the backend
   */
  Hierarchy.prototype.refresh = function() {
    var self = this;

    $.ajax({
      async: false,
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
        $.blockUI({message:"<h1>Refreshing ...</h1>"});
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
        self.reset();
      }
    });
  };

  /***************************************************************************
   * clear any selection
   */
  Hierarchy.prototype.clear = function() {
    var self = this;
    self.inputField.val("");
    self.worker.jstree("refresh", -1);
  };

  /***************************************************************************
   * confirm dialog
   */
  Hierarchy.prototype.confirm = function(opts) {
    var defaults = {
      message: "",
      title: "Confirmation required",
      okayText: "Ok",
      okayIcon: "ui-icon-check",
      cancelText: "Cancel",
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
          icons: {
            primary: opts.okayIcon
          },
          click: function() {
            $(this).dialog("close");
            dfd.resolve();
            return true;
          }
        }, {
          text: opts.cancelText,
          icons: {
            primary: opts.cancelIcon
          },
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
    defaults.url = foswiki.getPreference("SCRIPTURL")+"/rest/ClassificationPlugin/jsTreeConnector";

    /* enable class-based instantiation  */
    $(".jqHierarchy").livequery(function() {
      $(this).addClass("clearfix").hierarchy();
    });
  });

})(jQuery, window, document);
