"use strict";
jQuery(function($) {
   var natedit = $("textarea[name='SubCategories']").natedit({
      autoMaxExpand: true
   }).data("natedit");
   natedit.bottomHeight = 130;
});