jQuery(function($) {
   $(".clsCategoryContainer").livequery(function() {
      var $this = $(this),
          c, n = $this.find(".clsCategoryTile").length;
      if ($this.is(".cols2")) {
         c = 2;
      } else if ($this.is(".cols3")) {
         c = 3;
      } else if ($this.is(".cols4")) {
         c = 4;
      } else if ($this.is(".cols5")) {
         c = 5;
      }
      while (n % c) {
         $this.append("<div class='clsCategoryTile empty'></div>");
         n++;
      }
      $this.css("visibility", "visible");
   });
});