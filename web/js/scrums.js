/**
  * The contents of this file are subject to the Mozilla Public
  * License Version 1.1 (the "License"); you may not use this file
  * except in compliance with the License. You may obtain a copy of
  * the License at http://www.mozilla.org/MPL/
  *
  * Software distributed under the License is distributed on an "AS
  * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
  * implied. See the License for the specific language governing
  * rights and limitations under the License.
  *
  * The Original Code is the Scrums Bugzilla Extension.
  *
  * The Initial Developer of the Original Code is "Nokia Corporation"
  * Portions created by the Initial Developer are Copyright (C) 2011 the
  * Initial Developer. All Rights Reserved.
  *
  * Contributor(s):
  *   Eero Heino <eero.heino@nokia.com>
  */

function toggle_scroll()
{
    $('.content div').each(function (i, item)
    {
        $(item).toggleClass('autoheight');
    });
}

function listObject(ul_id, h_id, id, name, li_tmpl_function, link_url, offset_step) 
{
    this.ul_id = ul_id;
    this.id = id;
    this.h_id = h_id;
    this.link_url = link_url;
    this.list = [];
    this.orginal_list = [];
    this.visible = -1;
    this.offset = 0;
    if(offset_step)
    {
        this.offset_step = offset_step;
    }
    else
    {
        this.offset_step = 99999; // default value
    }
    this.name = name;
    this.line_template_function = li_tmpl_function;
    this.show_columns = ['order', 'bug_id', 'points', 'summary'];
    this.show_priority = true;
    this.show_creation_date = false;
    this.show_severity = false;

    this.estimatedcapacity = null;
    this.personcapacity = null;
    this.pred_estimate = "-";
    this.history = "";

    this.originally_contains_item = function (ref_item_id)
    {
	for(var i = 0; i < this.original_list.length; i++)
	{
	    if(this.original_list[i][0][0] == ref_item_id)
	    {
		return true;
	    }
	}
	return false;
    }
}

var from_list_ul_id = '';

var sprint_callback = null;

function search_link_sprint_items(sprint_id)
{
    var link_url = "buglist.cgi?query_format=advanced&";
    link_url += "columnlist=bug_severity%2Cpriority%2Cassigned_to%2Cbug_status%2Cshort_desc%2Cestimated_time%2Cactual_time%2Cremaining_time%2Cscrums_team_order%2Cscrums_blocked%2Csprint_name&";
    link_url += "order=scrums_team_order&";
    link_url += "field0-0-0=scrums_sprint_bug_map.sprint_id&type0-0-0=equals&value0-0-0=" + sprint_id;
    return link_url;
}

function select_step(list_id)
{
    var sel = document.getElementById(list_id);
    var val = new Number(sel.value); // Val becomes 0, if sel.value equals "all"

    for (var i = 0; i< all_lists.length; i++)
    {
        if (all_lists[i].id == list_id)
        {
	    if(sel.value == "All")
	    {
	    	val = all_lists[i].list.length;
		all_lists[i].offset = 0;
	    }
	    all_lists[i].offset_step = val;
	    all_lists[i].visible = -1;
	    update_lists(all_lists[i]);
            break;
        }
    }
}

function update_positions(lists, index, init_sorter)
{
    if (bug_positions.length < index +1)
    {
        bug_positions.push({});
    } else
    {
        bug_positions[index] = {};
    }

    for (var i = 0; i < lists[index].list.length; i++)
    {
        bug_positions[index][lists[index].list[i][0][0]] = i;
    }

    if (init_sorter && init_sorter != undefined)
    {
        $("#table"+lists[index].ul_id).tablesorter();
    } else
    {
        var table = $("#table"+lists[index].ul_id);
        table.trigger("update");
    }

    //$("#table"+bugs_list.ul_id).tablesorter({locale: 'de', useUI: false});
    $('#items_' + lists[index].id).html(parseInt(lists[index].list.length));
}

function switch_lists(ui, lists) {

    var bug_id = ui.item.attr('id');

    var to_i;
    var from_i;
    var old_position = parseInt(ui.item.attr('bug_order_nr') - 1);
    var to_list_ul_id = ui.item.parent().attr('id');

    for (var l = 0; l < lists.length; l++) {
        list = lists[l];
        if (list.ul_id == to_list_ul_id) {
            to_i = l;
        }
        if (list.ul_id == from_list_ul_id) {	
            from_i = l;
        }
    }

    var skip_rows = 0;
    var prev_bug_id = -1;
    $("#" + lists[to_i].ul_id).children('tr').each(function(position, elem)
    {
        if ($(elem).attr('id') == '')
        {
            skip_rows++;
            $(elem).remove();
            return true;
        }
        position -= skip_rows;
        if ($(elem).attr('id') == bug_id)
        {
            if (prev_bug_id > -1)
            {
                position = bug_positions[to_i][prev_bug_id] + 1;
            }
            //lists[to_i].list.splice(position, 0, lists[from_i].list.splice(old_position, 1)[0]);
            var temp = lists[from_i].list.splice(old_position, 1);
	    if(to_i == from_i && old_position < position) 
            {
            	lists[to_i].list.splice(position-1, 0, temp[0]);
	    }
	    else
	    {
            	lists[to_i].list.splice(position, 0, temp[0]);
	    }

            update_positions(lists, to_i);
            update_positions(lists, from_i);

	    if(sprint_callback) {
                sprint_callback(lists[0].estimatedcapacity, lists[0].list, lists[1].list);
	    }
        }
        prev_bug_id = $(elem).attr('id');
    });

    //rewrite to list
    $("#" + lists[to_i].ul_id).children('tr').each(function(position, elem)
    {
        var index = bug_positions[to_i][$(elem).attr('id')];
        var bug = lists[to_i].list[index];
        var counter = index + 1;
        var li_html = lists[to_i].line_template_function(bug, counter, lists[to_i].show_columns);

        $(elem).replaceWith(li_html);
    });

    //rewrite from-list
    if(from_i != to_i) {
        $("#" + lists[from_i].ul_id).children('tr').each(function(position, elem)
        {
            index = bug_positions[from_i][$(elem).attr('id')];
	    bug = lists[from_i].list[index];
	    counter = index + 1;
            var li_html = lists[from_i].line_template_function(bug, counter, lists[from_i].show_columns);
            $(elem).replaceWith(li_html);
        });
    }

    if (!lists[from_i].list.length)
    {
        $("#" + lists[from_i].ul_id).html(get_noitems_html());
    }

    var changed = check_if_changed();

    var elem = $("#save_button");
    elem[0].disabled = !changed;

    $('#'+bug_id).children().each(function ()
    {
        $(this).effect( 'highlight', {color: '#404d6c'}, 1000 );
    });
}

function bind_sortable_lists(lists) {

    for (var l = 0; l < lists.length; l++)
    {
        list = lists[l];
        update_positions(lists, l, true);
    }

    ids = [];
    for (var i = 0; i < lists.length; i++) {
        ids.push("#" + lists[i].ul_id);
        // enable live search
        list_filter($("#" + lists[i].h_id), $("#" + lists[i].ul_id), lists[i]);
    }
    ids_str = ids.join(", ")
    $(ids_str).sortable({
        connectWith: ".connectedSortable",
        start: function(event, ui) {
            from_list_ul_id = ui.item.parent().attr('id');
        },
        stop: function(event, ui) {
            switch_lists(ui, lists);
//	    save_all();
        },
        items: 'tr:not(.ignoresortable)',
        helper: function(event , item)
        {
            return item.clone().attr('class', 'helper');
        },
    }).disableSelection();
}


function bind_items_to_list(bugs_list, item_rows)
{
    bugs_list.list = item_rows;
    //deep copy
    bugs_list.original_list = $.extend(true, [], item_rows);
    bugs_list.visible = -1;
}

function update_lists(bugs_list, move_pos)
{
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
	var remainder = bugs_list.visible.length % bugs_list.offset_step;
        var list_length = bugs_list.visible.length;
        bugs_list.offset = list_length - remainder;
    }
    if (bugs_list.offset >= bugs_list.visible.length) {
        bugs_list.offset = 0;
    }


    var html = '';
    for (var i = bugs_list.offset; i < bugs_list.visible.length; i++) {

        if (i > bugs_list.offset + bugs_list.offset_step - 1) {
            break;
        }

        var index = bugs_list.visible[i];
        var bug = bugs_list.list[index];
        var counter = index + 1;
        html += bugs_list.line_template_function(bug, counter, bugs_list.show_columns);
    } // for

    if (html)
    {
        $("#" + bugs_list.ul_id).html(html);
    } else
    {
        $("#" + bugs_list.ul_id).html(get_noitems_html());
    }
}

function get_noitems_html()
{
    return '<tr><td colspan="6">&nbsp;</td></tr><tr class="ignoresortable"><td colspan="6" align="center">No Items</td></tr>';
}

function list_filter(header, list, bugs_list) { // header is any element, list is an unordered list
    // create and add the filter form to the header
    var form = $("<form>").attr({
        "class": "filterform",
        "action": "#"
    }),
    input = $("<input>").attr({
        "class": "filterinput",
        "type": "text",
        "style": "width: 70%;"
    });
        
    $(form).append('Filter: ').prependTo($(header).next());
    $(form).append(input).prependTo($(header).next());

    $(input).change(function() {
        var filter = $(this).val();
        if (filter) {
            bugs_list.visible = [];
            for (var i = 0; i < bugs_list.list.length; i++) {
                // search against desc and bug id
                var rg = new RegExp(filter,'i');
                // summary, assigned to and bug id
                if (bugs_list.list[i][5].search(rg) >= 0 || bugs_list.list[i][3].search(rg) >= 0 || String(bugs_list.list[i][0]).match("^" + filter) == filter) {
                    bugs_list.visible.push(i);
                }
            }
        } else {
            //show all
            bugs_list.visible = -1;
        }
        // reset offset when doing live search
        bugs_list.offset = 0;
        update_lists(bugs_list);
        return false;
    }).keyup(function() {
        // fire the above change event after every letter
        $(this).change();
    });
}

function move_list_left(list_id)
{
    move_list(list_id, true);
}
function move_list_right(list_id)
{
    move_list(list_id, false);
}

function move_list(list_id, left)
{
    for (var i = 0; i< all_lists.length; i++)
    {
        if (all_lists[i].id == list_id)
        {
	    if(left)
            {
                update_lists(all_lists[i], -all_lists[i].offset_step);
	    }
            else
            {
	        update_lists(all_lists[i], all_lists[i].offset_step);
            }
            break;
        }
    }
}

function saveResponse(response, status, xhr) 
{ 
	var retObj = eval("("+ response+")");
	if(retObj.errors)
	{
		alert(retObj.errormsg);
	}
	else
	{
    	    var elem = $("#save_button");
            elem[0].disabled = true;
		//alert("Success");
	}
}



function check_if_changed()
{
    for (var z = 0; z < all_lists.length; z++) 
    {
        var list = all_lists[z];
	if(list.list.length != list.original_list.length)
	{
	    return true;
	}
        for (var i = 0; i < list.list.length; i++) 
        {
	    if(list.id == -1)
            {
		if (list.originally_contains_item(list.list[i][0][0]) == false)
		{
		    return true;
		}
	    }
	    else
	    {
	    	if(list.list[i][0][0] != list.original_list[i][0][0])
	    	{
		    return true;
	 	}
	    }

        }
    }
    return false; // Content not changed
}

function detect_unsaved_change()
{
    if(check_if_changed())
    {
	if(confirm('There are unsaved changes. Changes would be lost. Save before continuing to exit?'))
	{
	    save_all();
	    return true; // Content changed permanently
	}
	else
	{
	    return false;
	}
    }
}


function do_save(saved_lists)
{
    var unordered_list = null;
    var ordered_lists = new Array();
    for (var i = 0; i < saved_lists.length; i++)
    {
	if(saved_lists[i].id == -1)
        {
	    unordered_list = saved_lists[i];
	}
	else
	{
	    ordered_lists.push(saved_lists[i]);
	}
    }
    save_lists(ordered_lists, unordered_list, schema, object_id);
}

function save_lists(ordered_lists, unordered_list, schema, obj_id)
{
    // need to use Object instead of Array when ajaxing an associative array
    var data_lists = new Object();

    if(unordered_list)
    {
        var list_id = String(-1);
        data_lists[list_id] = [];
        for (var i = 0; i < unordered_list.list.length; i++)
        {
            var found = false;
            for (var k = 0; k < unordered_list.original_list.length; k++)
            {
                if (unordered_list.original_list[k][0][0] == unordered_list.list[i][0][0])
                {
                    found = true;
                    break;
                }
            }
            if (found != true)
            {
                // this bug is new in unordered list
                data_lists[list_id].push(unordered_list.list[i][0][0])
            }
	}
    }
    save(ordered_lists, schema, obj_id, data_lists);

    if(unordered_list)
    {
        unordered_list.original_list = $.extend(true, [], unordered_list.list);
    }
    for (var i = 0; i < ordered_lists.length; i++)
    {
	var list = ordered_lists[i];
        list.original_list = $.extend(true, [], list.list);
    }
}

function save(lists, schema, obj_id, data_lists) {
    if (data_lists == undefined) {
        var data_lists = new Object();
    }
    for (var i = 0; i < lists.length; i++) {
        var list = lists[i];
        var list_id = list.id;
        data_lists[list_id] = [];
        for (var k = 0; k < list.list.length; k++) {
            data_lists[list_id].push(list.list[k][0][0]);
        }
    }

    var original_lists = new Object();
    for (var i = 0; i < lists.length; i++) {
        var list = lists[i];
        var list_id = list.id;
        original_lists[list_id] = [];
        for (var k = 0; k < list.original_list.length; k++) {
            original_lists[list_id].push(list.original_list[k][0][0]);
        }
    }

    $.post('page.cgi?id=scrums/ajax.html', {
        schema: schema,
        action: 'set',
        obj_id: obj_id,
        data: JSON.stringify({"data_lists" : data_lists, "original_lists" : original_lists})
    }, saveResponse        , 'text');
}

