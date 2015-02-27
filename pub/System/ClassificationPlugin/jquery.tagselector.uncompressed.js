/*
 * jQuery TagSelector plugin 1.1
 *
 * Copyright (c) 2008-2015 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
(function($) {
"use strict";

  /***************************************************************************
   * plugin definition 
   */
  $.fn.tagSelector = function(options) {
    $.log("called tagSelector()");
   
    // build main options before element iteration
    var opts = $.extend({}, $.fn.tagSelector.defaults, options);
   
    // implementation ********************************************************
    return this.each(function() {
      $this = $(this);

      // build element specific options. 
      // note you may want to install the Metadata plugin
      var thisOpt = $.extend({}, opts, $this.data());

      // get interface elements
      var $input = $this.find(thisOpt.input);
      var $tagCloud = $this.find(thisOpt.tagCloud)
      var $tagContainer = $this.find(thisOpt.tagContainer);

      //$.log("input="+$input);
      //$.log("tagCloud="+$tagCloud);
      //$.log("tagContainer="+thisOpt.tagContainer);

      var initialTags;

      // toggle a tag in the input field and the cloud ***********************
      function toggleTag(tag) {
        $.log("called toggleTag("+tag+")");

        var found = false;
        var newValues = new Array();
        $this.find('.clsTag input').each(function() {
          var value = $(this).val();
          if (value) {
            if (value == tag) {
              found = true;
            } else {
              if (value.indexOf(tag) != 0) {
                newValues.push(value);
              }
            }
          }
        });

        if (!found) {
          newValues.push(tag)
        }
        //$.log("newValues="+newValues);

        setTags(newValues);
      }

      // add a tag to the selection ******************************************
      function setTags(tags) {
        //$.log("called setTags("+tags+")");

        clearSelection();
        var values;
        if (typeof(tags) == 'object') {
          values = tags;
        } else {
          values = tags.split(/\s*,\s*/);
        }
        if (!values.length) {
          return;
        }
        var tmpValues = new Array()
        for (var i = 0; i < values.length; i++) {
          tmpValues.push(values[i].replace(/([^0-9A-Za-z_])/g, '\\$1'));
        }
        var filter = "#"+tmpValues.join(",#");
        //$.log("filter="+filter);
        $tagCloud.find(filter).addClass("current");
        if (thisOpt.doSort) {
          values = values.sort();
        }

        $(".clsTag").remove();
        for (var i = values.length-1; i >= 0; i--) {
          var value = values[i];
          var input = "<input type='hidden' name='"+thisOpt.name+"' value='"+value+"' />";
          var $close = $("<a class='clsTagClose' href='#' title='remove "+value+"'></a>");
          $close.click(function() {
            toggleTag($(this).parent().find('input').val());
            return false;
          });
          var $clsTag = $("<span class='clsTag'></span>").append(input).append($close).append(value);
          $tagContainer.prepend($clsTag);
        }
      }

      // clear selection *****************************************************
      function clearSelection() {
        $this.find(".clsTag").remove();
        $tagCloud.find("a").removeClass('current typed');
      }
 
      // reset selection *****************************************************
      function resetSelection() {
        setTags(initialTags);
      }

      // init ****************************************************************
      function init() {
        // events 
        $.log("called init()");
        var tags = [];
        $this.find('.clsTagCloud a').each(function() {
          tags.push([$(this).text(),$(this).attr('title')]);
        });
        $.log("tags = "+tags);
        $input.autocomplete(
          tags,
          {
            selectFirst:false,
            autoFill:false,
            matchCase:false,
            matchSubset:true,
            formatItem: function(tag, i, total) {
              return '<table width="100%"><tr><td align="left">'+tag[0]+'</td><td align="right">'+tag[1]+'</td></tr></table>';
            },
            formatMatch: function(tag, i, total) {
              return tag[0];
            }
          }
        ).result(function(event, data, formatted) {
          $.log("result: formatted="+formatted);
          toggleTag(formatted);
          $input.val('');
        });
        $(thisOpt.clearButton, $this).click(function() {
          clearSelection();
          this.blur();
          return false;
        });
        $(thisOpt.resetButton, $this).click(function() {
          resetSelection();
          this.blur();
          return false;
        });

        initialTags = new Array();
        // tag cloud links
        $tagCloud.find("a").click(function() {
          $.log("click");
          this.blur(); 
          toggleTag($(this).attr('id'));
        }).filter(".current").each(function() {
          var term = $(this).attr('id');
          initialTags.push(term);
        });

        resetSelection();

	$input.bind(($.browser.opera ? "keypress" : "keydown") + ".autocomplete", function(event) {
          // track last key pressed
          if(event.keyCode == 13) {
            var value = $input.val();
            if (value) {
              toggleTag(value);
              $input.val('');
              return false;
            }
          }
        });
      }

      init();
    });
  };

  /***************************************************************************
   * plugin defaults
   */
  $.fn.tagSelector.defaults = {
    debug: false,
    input: ".clsTagCloudInput",
    tagCloud: ".clsTagCloud",
    tagContainer: ".clsTagContainer",
    clearButton: ".clsClearButton",
    resetButton: ".clsResetButton",
    doSort: false,
    name: "tag"
  };

 
})(jQuery);
