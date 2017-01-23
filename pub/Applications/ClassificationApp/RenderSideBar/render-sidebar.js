"use strict";
  jQuery(function ($) {
    $("#clsSideBarCategoryBrowser > ul").each(function() {
      var $this = $(this);
      $this.find("li ul").parent().addClass("open collapsable");
      $this.find(".placeholder").parent().parent().parent().removeClass("open collapsable");
      $this.find(".hasChildren.open").removeClass("hasChildren");
      $this.treeview({
        url: "https://localhost/bin/rest/RenderPlugin/tag?name=DBCALL;param=Applications.ClassificationApp.RenderHierarchyAsJSON;t=1465571741;depth=2;format=sidebar;topic=Applications/ClassificationApp.RenderSideBar",
        animated: 'fast'
      }).parent().show();
      $this.find(".open").removeClass("expandable").
      find(".open-hitarea.expandable-hitarea").removeClass("expandable-hitarea").addClass("collapsable-hitarea");
    });
  });