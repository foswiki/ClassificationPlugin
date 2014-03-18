jQuery(function($) {
  "use strict";

  $(".clsTagSuggestion:not(.jqInitedTagSuggestion)").livequery(function() {
    var $this = $(this), 
        $input = $this.parents(".clsTagEditor").find(".jqTextboxList:first"),
        val = $this.text();

    $this.addClass("jqInitedTagSuggestion");
    $this.click(function(e) {
      $input.trigger("AddValue", val);
      $this.parent().remove();
      e.preventDefault();
      return false;
    });
  });
});
