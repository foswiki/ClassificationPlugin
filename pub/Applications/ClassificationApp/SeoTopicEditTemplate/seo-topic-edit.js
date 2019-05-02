"use strict";
jQuery(function($) {
  $(document).on("click", "#clsGenerateTitle", function() {
    $(this).parents(".foswikiFormStep:first").find("input").val($("input[name=TopicTitle]").val());
    return false;
  });

  $(document).on("click", "#clsGenerateDescription", function() {
    var $field = $(this).parents(".foswikiFormStep:first").find("textarea"),
        description = $("input[name=Summary]").val();

    if (!description) {
      description = $("#topic").val();
    }

    $field.val(description.replace(/<[^>]*>/g, "").replace(/\n\s*\n/g, "").substr(0, 160));
    return false;
  });

  $(document).on("click", "#clsGenerateKeywords", function() {
    var $field = $(this).parents(".foswikiFormStep:first").find("input"),
        keywords = [];

    $("input[name=Tag], input[name=Category]").each(function() {
      var vals = $.trim($(this).val()).split(/\s*,\s*/);
      $.each(vals, function(index, val) {
        val = val.replace(/Category$/, "");
        if (val) {
          keywords.push(val);
        }
      });
    });

    $field.val(keywords.join(", "));
    return false;
  });
});