function listObject(ul_id, h_id, id, name) {
    this.ul_id = ul_id;
    this.id = id;
    this.h_id = h_id;
    this.list = [];
    this.orginal_list = [];
    this.visible = -1;
    this.offset = 0;
    this.name = name;
}
var offset_step = 10;
var from_list_ul_id = '';

function switch_lists(ui, lists) {
    to_list_ul_id = ui.item.parent().attr('id');
    old_position = parseInt(ui.item.find('span.number').text() - 1);
    old_vis_position = parseInt(ui.item.attr('bug_order_nr'));
    to_list = undefined;
    from_list = undefined;
    new_position = -1;
    for (var l = 0; l < lists.length; l++) {
        list = lists[l];
        if (list.ul_id == to_list_ul_id) {
            to_list = list;
        }
        if (list.ul_id == from_list_ul_id) {
            from_list = list;
        }
    }
    $("#" + to_list.ul_id).find('li').each(function(i) {
        if (to_list.visible.length == to_list.offset + i) {
            if (to_list.visible.length > 0) {
                // new value is plus one from the prev last
                to_list.visible.push(to_list.visible[to_list.visible.length - 1] + 1)
            } else {
                // first item in the list
                to_list.visible.push(0);
            }
            //alert('list '+to_list.list.length);
        }
        order = to_list.visible[to_list.offset + i];
        if ($(this).attr('id') == ui.item.attr('id')) {
            new_position = order;
            to_list.list.splice(new_position, 0, from_list.list[old_position]);
            from_list.list.splice(old_position, 1);
            from_list.visible.splice(old_vis_position, 1);
            //alert(to_list.visible.length);
            vis_position = to_list.offset + i;
            return false;
        }
    });
    //FIXME nicer way to handle changes (than recreating the lists)!
    to_list.visible = -1;
    from_list.visible = -1;
    update_lists(to_list);
    update_lists(from_list);
}

function bind_sortable_lists(lists) {
    // DEMO
    //$( "#sortable1, #sortable2, #demo1, #demo2"  ).sortable({
    ids = [];
    for (var i = 0; i < lists.length; i++) {
        ids.push("#" + lists[i].ul_id);
    }
    ids_str = ids.join(", ")
    $(ids_str).sortable({
        connectWith: ".connectedSortable",
        start: function(event, ui) {
            from_list_ul_id = ui.item.parent().attr('id');
        },
        stop: function(event, ui) {
            switch_lists(ui, lists);;
        }
    }).disableSelection();
}

function update_lists(bugs_list, move_pos, data) {
    if (data != undefined) {
        bugs_list.list = data;
        //deep copy
        bugs_list.original_list = $.extend(true, [], data);
        bugs_list.visible = -1;
    }
    if (bugs_list.visible == -1) {
        // show all
        bugs_list.visible = [];
        for (var i = 0; i < bugs_list.list.length; i++) {
            bugs_list.visible.push(i);
        }
    }
    if (move_pos == undefined) {
        move_pos = 0;
    }
    bugs_list.offset += move_pos;
    if (bugs_list.offset < 0) {
        bugs_list.offset = bugs_list.visible.length - (bugs_list.visible.length % offset_step);
    }
    if (bugs_list.offset >= bugs_list.visible.length) {
        bugs_list.offset = 0;
    }
    html = "";
    //for(var i = bugs_list.offset; i < bugs_list.list.length; i++) {
    for (var i = bugs_list.offset; i < bugs_list.visible.length; i++) {
        if (i > bugs_list.offset + offset_step - 1) {
            break;
        }
        html += parseTemplate($("#BugLiTmpl").html(), {
            bug: bugs_list.list[bugs_list.visible[i]],
            counter: (bugs_list.visible[i] + 1)
        });
    }
    $("#" + bugs_list.ul_id).html(html);
}

function listFilter(header, list, bugs_list) { // header is any element, list is an unordered list
    // create and add the filter form to the header
    var form = $("<form>").attr({
        "class": "filterform",
        "action": "#"
    }),
        input = $("<input>").attr({
            "class": "filterinput",
            "type": "text"
        });
    $(form).append(input).appendTo("#" + header);
    $(input).change(function() {
        var filter = $(this).val();
        if (filter) {
            bugs_list.visible = [];
            for (var i = 0; i < bugs_list.list.length; i++) {
                // search against desc and bug id
                if (bugs_list.list[i][3].toLowerCase().match("^" + filter.toLowerCase()) == filter.toLowerCase() || bugs_list.list[i][0].match("^" + filter) == filter) {
                    //filtered_bugs.list.push(bugs_list.list[i]);
                    bugs_list.visible.push(i);
                }
            }
            // this finds all links in a list that contain the input,
            // and hide the ones not containing the input while showing the ones that do
            //$(list).find("a:not(:Contains(" + filter + "))").parent().hide();
            //$(list).find("a:Contains(" + filter + ")").parent().show();
            //update_lists("#sortable2", filtered_bugs);
        } else {
            //show all
            bugs_list.visible = -1;
        }
        //$(list).find("li").show();
        // reset offset when doing live search
        bugs_list.offset = 0;
        update_lists(bugs_list);
        return false;
    }).keyup(function() {
        // fire the above change event after every letter
        $(this).change();
    });
}(function($) {
    // custom css expression for a case-insensitive contains()
    //  jQuery.expr[':'].Contains = function(a,i,m){
    //     return (a.textContent || a.innerText || "").toUpperCase().indexOf(m[3].toUpperCase())>=0;
    //};
/*
  //ondomready
  $(function () {
    $.post('page.cgi?id=scrums/release_ajax.html', {action: 'fetch', releaseid: [% release.id %]}, function (data) { update_lists(ordered_bugs, 0, data[0]); update_lists(unordered_bugs, 0, data[1]) }, 'json');
    //update_lists(ordered_bugs);
    listFilter($("#headers2"), $(unordered_bugs.ul_id), unordered_bugs);
    listFilter($("#headers"), $(ordered_bugs.ul_id), ordered_bugs);

    // DEMO
//    update_lists(demo1);
//    update_lists(demo2);
//    listFilter($("#headers3"), $(demo1.ul_id), demo1);
//    listFilter($("#headers4"), $(demo2.ul_id), demo2);
  }); */
}(jQuery));

function init(schema, obj_id, lists) {
    // DEMO
    //var demo1 = new listObject("#demo1");
    //var demo2 = new listObject("#demo2");

    function call_back(data) {
        for (var i = 0; i < lists.length; i++) {
            update_lists(lists[i], 0, data[i]);
            listFilter($(lists[i].h_id), $("#" + lists[i].ul_id), lists[i]);
        }
    }
    $.post('page.cgi?id=scrums/ajax.html', {
        schema: schema,
        action: 'fetch',
        obj_id: obj_id
    }, call_back, 'json');
    //update_lists(ordered_bugs);
    bind_sortable_lists(lists);
    // DEMO
    //    update_lists(demo1);
    //    update_lists(demo2);
    //    listFilter($("#headers3"), $(demo1.ul_id), demo1);
    //    listFilter($("#headers4"), $(demo2.ul_id), demo2);
}

function save(lists, schema, obj_id, data_lists) {
    if (data_lists == undefined) {
        var data_lists = new Array();
    }
    for (var i = 0; i < lists.length; i++) {
        var list = lists[i];
        data_lists[list.id] = [];
        for (var k = 0; k < list.list.length; k++) {
            data_lists[list.id].push(list.list[k][0]);
        }
    }
    $.post('page.cgi?id=scrums/ajax.html', {
        schema: schema,
        action: 'set',
        obj_id: obj_id,
        data: data_lists
    }, function() {}, 'json');
}
