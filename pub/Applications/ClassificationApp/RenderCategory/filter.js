"use strict"
jQuery(function($) {
   var $container = $(".clsMakeIndexWrapper"), timer;
   function updateCategoryIndex(val) {
      $container.find(".fltMakeIndexItem").each(function() { 
         var $this = $(this), text = $this.text(); 
         if (!regex.test(text)) { 
            $this.fadeOut(); 
         } else {
            if (!$this.is(":visible")) {
               $this.fadeIn();
            }
         }
      });
   }
   $("input.clsFilter").on("keyup", function(ev) { 
      var $this = $(this), val = $this.val(); 
      if (typeof(timer) !== 'undefined') {
         window.clearTimeout(timer);
      }
      timer = window.setTimeout(function() { 
         updateCategoryIndex(val); 
         timer = undefined;
      }, 500);
   });
});