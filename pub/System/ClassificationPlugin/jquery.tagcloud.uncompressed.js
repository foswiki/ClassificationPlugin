(function($) {
"use strict";

  function toggleItem(list, opts) {
    var split = opts.split;
    var remove = opts.remove;
    if (remove) {
      remove = new RegExp(remove.split(/\s*,\s*/).join('|'));
    }
    if (typeof(split) == 'undefined') {
      split = /\s*,\s*/;
    } else {
      split = new RegExp(split);
    }
    if (typeof(list) == 'string') {
      list = list.split(split);
    }
    var newList = new Array();
    var found = 0;
    for (var i = 0, len = list.length; i < len; i++) {
      var listItem = list[i];
      if (remove && remove.test(listItem)) {
        continue;
      }
      if (listItem === opts.item) {
        found = 1;
      } else {
        if (listItem) {
          newList.push(listItem);
        }
      }
    }
    if (!found && opts.item) {
      newList.push(opts.item)
    }
    return newList;
  }

$.fn.tagCloud = function(options) {
  return this.each(function() {
    var $form = $(this);
    var inputs = {
      tag:$form.find("input[name=tag]"),
      cat:$form.find("input[name=cat]"),
      topictype:$form.find("input[name=topictype]"),
      search:$form.find("input[name=search]")
    };

    $(".tagCloudToggle").click(function() {
      var $this = $(this);
      var opts = $.extend({}, $this.metadata());
      if (opts.item && opts.input) {
        var inputElem = inputs[opts.input];
        var newItems = toggleItem(inputElem.val(), opts);
        inputElem.val(newItems.join(", "));
        $form.submit();
      }
      return false;
    });

    $(".tagCloudSearch").bind(($.browser.opera ? "keypress" : "keydown"), function(event) {
      if(event.keyCode == 13) {
        var val = $(this).val();
        if (val) {
          var inputElem = inputs['search'];
          var newItems = toggleItem(inputElem.val(), {item:val, split:' '});
          inputElem.val(newItems.join(" "));
          $form.submit();
        }
      }
    });

    var $tc = $form.find(".clsTagCloud"); // doing a $form.find(".clsTagCloud a") does not work using jquery-1.3.2 and IE6+7
    $tc.find("a").click(function() {
      var clickedTag = $(this).attr('name');
      var newTags = toggleItem(inputs['tag'].val(), {item:clickedTag});
      inputs['tag'].val(newTags.join(", "));
      $form.submit();
      return false;
    });
  });
};

/* init */
$(function() {
  $(".tagCloudForm").tagCloud();
});

})(jQuery);

/* compatibility */
function submitTagCloud(clickedTag) {
}
