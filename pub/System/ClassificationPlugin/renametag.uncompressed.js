/*
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2018-2019 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

*/

/*global StrikeOne:false */
"use strict";

jQuery(function($) {

  $(".jqRenameTag").each(function() {
    // ajaxification of renametagform
    var $this = $(this),
        opts = $.extend({}, $this.metadata());

    $this.ajaxForm({
        dataType: 'json',
        beforeSerialize: function() {
          if (typeof(foswikiStrikeOne) !== 'undefined') {
            foswikiStrikeOne($this[0]);
          }
        },
        beforeSubmit: function(data, form, options) {
          var from = new Array;
          $this.find("input[name=from]").each(function() {
            var val = $(this).val();
            if (val) {
              from.push(val);
            }
          });
          if (from.length == 0) {
            return false;
          }
          $("#renameTagDialog").dialog("close");
          $.blockUI({message:"<h1 class='i18n'> Processing ... </h1>"});
        },
        success: function(data, status) {
          var url = foswiki.getPreference("SCRIPTURL")+"/view/"+foswiki.getPreference("WEB")+"/"+foswiki.getPreference("TOPIC");
          $.unblockUI();
          $.blockUI({message:"<h1> "+data.result+"</h1>"});
          if (typeof(opts.onsuccess) == 'function') {
            opts.onsuccess.call(this, $this);
          }
          window.setTimeout(function() {
            window.location.href = url;
          }, 500);
        },
        error: function(xhr, status) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $.blockUI({message:"<h1 class='i18n'> "+data.error.message+"</h1>"});
          window.setTimeout(function() {
            $.unblockUI();
            if (typeof(opts.onerror) == 'function') {
              opts.onerror.call(this, $this);
            }
          }, 1000);
        }
    });
  });
});
