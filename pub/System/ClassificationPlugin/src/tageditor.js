/*
 * jQuery Tag Editor 1.20
 *
 * Copyright (c) 2018-2026 Michael Daum http://michaeldaumconsulting.com
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
    self.opts = $.extend({
      web: foswiki.getPreference("WEB"),
      topic: foswiki.getPreference("TOPIC"),
    }, defaults, self.elem.data(), opts);

    self.init();
  }

  TagEditor.prototype.init = function () {
    var self = this;

    self.input = self.elem.find("input.jqTextboxList");
    self.container = self.elem.find(".jqTagSuggestions");
    self.input.on("DeleteValue SelectValue refresh", function(ev, data) {
      self.getTagSuggestions();
    });

    window.setTimeout(function() {
      self.getTagSuggestions();
    }, 500);
  };

  TagEditor.prototype.getTags = function() {
    var self = this,
      delegate = self.input.data("textboxlist");

    return delegate ? delegate.currentValues : [];
  };

  TagEditor.prototype.getTagSuggestions = function() {
    var self = this,
        suggestions = self.container.find("ol"),
        url = foswiki.getScriptUrlPath("rest", "RenderPlugin", "template"),
        tags = self.getTags();

    //console.log("tags=",tags);
    self.container.block({message:""});

    $.post(url, {
      web: self.opts.web,
      topic: self.opts.web + "." + self.opts.topic,
      name: "classificationplugin",
      expand: "suggesttags",
      contenttype: "application/json",
      tags: tags.join(", ")
    }).done(function(data) {
      self.container.unblock();
      suggestions.empty();
      if (data.length) {
        $.each(data, function(i, item) {
          $(`<li><a href='#' title='${$.i18n("click to add")}'>${item.key}</a></li>`).on("click", function() {
            self.addVal(item.key);
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
    $(".jqTagEditor").livequery(function() {
      $(this).tagEditor();
    });
  });

})(jQuery);
