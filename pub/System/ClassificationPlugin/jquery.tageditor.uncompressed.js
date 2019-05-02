/*
 * jQuery Tag Editor 1.0
 *
 * Copyright (c) 2018-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($) {

  // Create the defaults once
  var defaults = {};

  // The plugin constructor
  function TagEditor(elem, opts) {
    var self = this;

    self.elem = $(elem);

    // gather options by merging global defaults, plugin defaults and element defaults
    self.opts = $.extend({}, defaults, self.elem.data(), opts);
    self.init();
  }

  TagEditor.prototype.init = function () {
    var self = this;

    self.input = self.elem.find("input.jqTextboxList");
    self.container = self.elem.find(".jqTagSuggestions");
    self.getTagSuggestions();
    self.input.on("DeleteValue, SelectedValue", function(ev, data) {
      //console.log("changed values data=",data);
      self.getTagSuggestions();
    });
  };

  TagEditor.prototype.getTags = function() {
    var self = this, vals = [];

    // OUTCH
    self.elem.find(".jqTextboxListValue > input").each(function() {
      vals.push($(this).val());
    });

    return vals;
  };

  TagEditor.prototype.getTagSuggestions = function() {
    var self = this,
        suggestions = self.container.find("ol"),
        tags = self.getTags();

    self.container.block({message:""});

    $.get(self.opts.tagSuggestionUrl+";tags="+encodeURIComponent(tags)).done(function(data) {
      self.container.unblock();
      suggestions.empty();
      if (data.length) {
        $.each(data, function(i, item) {
          $("<li><a href='#'>"+item.key+"</a></li>").on("click", function() {
            self.addVal(item.key);
            self.getTagSuggestions();
            return false;
          }).appendTo(suggestions);
        });
        self.container.show();
      } else {
        self.container.hide();
      }
    });
  };

  TagEditor.prototype.addVal = function(val) {
    var self = this;

    self.input.trigger("AddValue", val);
  };

  // A plugin wrapper around the constructor,
  // preventing against multiple instantiations
  $.fn.tagEditor = function (opts) {
    return this.each(function () {
      if (!$.data(this, "TagEditor")) {
        $.data(this, "TagEditor", new TagEditor(this, opts));
      }
    });
  };

  // Enable declarative widget instanziation
  $(function() {
    $(".jqTagEditor:not(.jqTagEditorInited)").livequery(function() {
      $(this).addClass("jqTagEditorInited").tagEditor();
    });
  });

})(jQuery);

