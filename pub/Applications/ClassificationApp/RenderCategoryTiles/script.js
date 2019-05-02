jQuery(function($) {
  $("h1.clsCategoryTitle").livequery(function() {
   $(this).autoColor({
      target: ".jqIcon",
      property: "color",
      lightness: "50"
   });
  });
});