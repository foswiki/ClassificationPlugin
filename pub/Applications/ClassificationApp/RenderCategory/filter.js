"use strict";
(function($) {
   $(".clsMakeIndexWrapper").livequery(function() {
      var $container = $(this), 
         $input = $container.find(".clsFilter"),
         timer;

      function updateCategoryIndex(val) {
         $container.find(".fltMakeIndexItem").each(function() { 
            var $this = $(this), 
               text = $this.text().replace(/­/g, ""),
               regex = new RegExp(val, "i");

            if (!regex.test(text)) { 
               $this.hide(); 
            } else {
               if (!$this.is(":visible")) {
                  $this.fadeIn();
               }
            }
         });
      }

      $input.on("search", function(ev) { 
         var $this = $(this), 
            val = $this.val();

         if (typeof(timer) !== 'undefined') {
            window.clearTimeout(timer);
         }
         timer = window.setTimeout(function() { 
            updateCategoryIndex(val); 
            timer = undefined;
         }, 250);
      });
   });
})(jQuery);