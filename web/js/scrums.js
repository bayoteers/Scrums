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

function create_item_line_html(bug, counter, show_columns)
{
    var str = '';
    if (bug[10]) {
        str += '<tr id=\'' + bug[0][0] + '\'  class="scrums_limited_area" bug_order_nr=\'' + counter + '\'>';
    }
    else {
        str += '<tr id=\'' + bug[0][0] + '\' bug_order_nr=\'' + counter + '\'>';
    }
    if ($.inArray('order', show_columns) > -1) { 
        str += '<td class=\'colF sortable\'> <span class=\'number\'>' + counter + '</span></td>';
    }
    if ($.inArray('bug_id', show_columns) > -1) {
	str += '<td class=\'colD sortable\'>' + bug[0][1] + '</td>';
    }
    if ($.inArray('points', show_columns) > -1) { 
	str += '<td class=\'colF sortable\'>' + bug[1] + '</td>';
    }
    if ($.inArray('status', show_columns) > -1) { 
	str += '<td class=\'colC sortable\'>' + bug[2] + '</td>';
    }
    if ($.inArray('assigned', show_columns) > -1) {
        str += '<td class=\'colA sortable\'>' + bug[3] + '</td>';
    }
    if ($.inArray('severity', show_columns) > -1) { 
        str += '<td class=\'colA sortable\'> ' + bug[7] + '</td>';
    }
    if ($.inArray('summary', show_columns) > -1) {  
	str += '<td title=\'' + bug[5] + '\' class=\'sortable\'> ' + bug[5] + '</td>';
    }
    if ($.inArray('creation_date', show_columns) > -1) {  
	str += '<td class=\'sortable\'>' + bug[6] + '</td>';
    }
    str += '</tr>';
    return str;
}

function create_list_html(list)
{
   var html = '<h3 id="' + list.h_id + '">'
   if(list.link_url)
   {
       html += '<a href="' + list.link_url + '">' + list.name + ' (<span id="items_' + list.id + '"></span>)</a>';
   }
   else
   {
       html += list.name;
   }
   html += '</h3>';
   html +=    '<div class="content" >';
   html +=      '<div class="scrollTableContainer" id="container">';
   html +=        '<table class="dataTable" id="table' + list.ul_id + '">';
   html +=          '<thead id="mythead">';
   html +=            '<tr>';
   if ($.inArray('order', list.show_columns) > -1) { 
       html += '<th class="sortable">#</th>';
   }
   if ($.inArray('bug_id', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_id + '</th>';
   }
   if ($.inArray('points', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.remaining_time + '</th>';
   }
   if ($.inArray('status', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_status + '</th>';
   }
   if ($.inArray('assigned', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.assigned_to + '</th>';
   }
   if ($.inArray('severity', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.bug_severity + '</th>';
   }
   if ($.inArray('summary', list.show_columns) > -1) {
       html += '<th class="sortable colF">' + field_descs.short_desc + '</th>';
   }
   if ($.inArray('creation_date', list.show_columns) > -1) {
       html += '<th class="sortable">' + field_descs.creation_ts + '</th>';
   }
   html +=            '</tr>';
   html +=          '</thead>';
   html +=        '<tbody id="' + list.ul_id + '" class="connectedSortable sortable">';
   html +=        '</tbody>';
   html +=      '</table>';
   html +=    '</div>';
   html +=  '</div>';
   return html;
}

function create_release_item_list_html(list) {
  var html = '<h3 id="' + list.h_id + '">' + list.name + '</h3>';
  html += '<div class="content">';
  html +=   '<p>';
  html +=     '<input type="button" value="Previous" OnClick=\'move_list_left("' + list.id + '");\'/>';
  html +=     '<input type="button" value="Next" OnClick=\'move_list_right("' + list.id + '");\'/>';
  html +=     'Show';
  html +=     '<select id="' + list.id + '" onchange=\'select_step("' + list.id + '");\'>';
  html +=       '<option>10</option>';
  html +=       '<option selected="selected">20</option>';
  html +=       '<option>50</option>';
  html +=       '<option>All</option>';
  html +=     '</select>';
  html +=     '(<span id="items_' + list.id + '"></span>)';
  html +=   '</p>';
  html +=   '<table class="dataTable">';
  html +=     '<thead>';
  html +=       '<tr>';
  html +=         '<th class="sortable">Priority</th>';
  html += 	  '<th class="sortable" class="colF">' + field_descs.bug_id + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.bug_status + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.bug_severity + '</th>';
  html +=         '<th class="sortable" class="colF">' + field_descs.short_desc + '</th>';
  html +=         '<th class="sortable" class="colF">Team</th>';
  html +=         '<th class="sortable" class="colF">Sprint</th>';
  html +=       '</tr>';
  html +=     '</thead>';
  html +=     '<tbody id="' + list.ul_id + '" class="connectedSortable sortable">';
  html +=     '</tbody>';
  html +=   '</table>';
  html += '</div>';
  return html;
}


function create_release_item_line(bug, counter, show_columns)
{
    var html = '<tr id="' + bug[0][0] + '" bug_order_nr="' + counter + '">';
    if ($.inArray('order', show_columns) > -1) {
        html += '<td class="colF"><span class="number">' + counter + '</span></td>';
    }
    if ($.inArray('creation_date', show_columns) > -1) {
        html += '<td class="sortable">' + bug[6] + '</td>';
    }
    html += '<td class="colD">' + bug[0][1] + '</td>';
    html += '<td class="colC">' + bug[1] + '</td>';
    html += '<td class="colD">' + bug[2] + '</td>';
    html += '<td class="colA">' + bug[3] + '</td>';
    if ($.inArray('severity', show_columns) > -1) {
        html += '<td class="colA sortable">' + bug[7] + '</td>';
    }
    html += '<td class="colB"><a href="page.cgi?id=scrums/createteam.html&teamid=' + bug[6] + '">' + bug[4] + '</a></td>';
    html += '<td><a href="page.cgi?id=scrums/sprintburndown.html&sprintid=' + bug[7] + '">' + bug[5] + '</a></td>';
    html += '</tr>';
    return html;
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

function show_sprint(result)
{
    data = result.data;
    if(result.errormsg != "")
    {
	alert(result.errormsg);
	return;
    }
    data = result.data;

    var sprint = all_lists[0];
    sprint._status = data._status;
    sprint.description = data.description;
    sprint.start_date = data.start_date;
    sprint.end_date = data.end_date;

    sprint.estimatedcapacity = data.estimatedcapacity
    sprint.personcapacity = data.personcapacity
    sprint.pred_estimate = data.prediction;
    sprint.history = data.history;

    sprint_info_showed = true;
    $('#sprint_info').html(sprint.start_date+' &mdash; '+sprint.end_date);
    $('#sprint_button').html("<input type='button' value='Edit Sprint' onClick='edit_sprint();'/>");

    check_receive_status();
}

function edit_sprint()
{
    sprint = all_lists[0];
    $('#sprint').html(parseTemplate($('#NewSprintTmpl').html(), { list: sprint, edit: true, sprintid: sprint.id }));
    $('#sprint_action').html('<h3>Edit Sprint</h3>');
    $("input[name=sprintname]").val(sprint.name.replace('Sprint ', ''));
    $("input[name=description]").val(sprint.description);
    $("input[name=start_date]").val(sprint.start_date);
    $("input[name=end_date]").val(sprint.end_date);
    $("input[name=submit]").val('Save');
    $('#personcapacity').html(sprint.personcapacity);
    $("input[name=estimatedcapacity]").val(sprint.estimatedcapacity);
    $('#estimate').html(sprint.pred_estimate);
    $('#history').html(sprint.history);
    // prepare Options Object 
    var options = { 
        success:   create_sprint,
        dataType: 'json'
        } 
    $('#new_sprint_form').ajaxForm(options);
        var range_begin = "";
        var range_end = "";

        var today = new Date();
        $("#datepicker_min").datepicker({ maxDate: today, dateFormat: 'yy-mm-dd' });
        $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
}

        function cancel()
        {
          window.location = "page.cgi?id=scrums/teambugs.html&teamid=[% teamid %]";  
        }

        function checkvalues()
        {
        gettime();

        //var sprintname = window.document.forms['newsprint'].elements['sprintname'].value;
        var sprintname = $('input[name=sprintname]').val();

        if(sprintname == '')
        {
          alert("Sprint must have name.");
          return false;
        }

        if(sprintname.match(/^\S/) == null)
        {
          alert("Sprint name can not start with whitespace");
          return false;
        }

        if(range_begin == "")
        {
            alert("Sprint must have start date");
            return false;
        }

        return true;
        }

        function askconfirm()
        {
        return confirm("Are you sure you want to delete sprint '[% sprintname %]'?");
        }

        function gettime() 
        {
            range_begin = $('#datepicker_min').val();
            range_end = $('#datepicker_max').val();
        }



function get_sprint()
{
    if ($('#selected_sprint').val() == 'new_sprint')
    {
        $('#sprint').html(parseTemplate($('#NewSprintTmpl').html(), { list: sprint, edit: false, sprintid: 0 }));
        $('#sprint_action').html('<h3>Create Sprint</h3>');
        
        var options = { 
            success:   create_sprint,
            dataType: 'json'
            } 
        $('#new_sprint_form').ajaxForm(options);

        var range_begin = "";
        var range_end = "";

        var today = new Date();
        $("#datepicker_min").datepicker({ maxDate: today, dateFormat: 'yy-mm-dd' });
        $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
        $('#history').html(sprint.history);
    } else
    {
            $.post('page.cgi?id=scrums/ajaxsprintbugs.html', {
            teamid: team_id,
            sprintid: $('#selected_sprint').val(),
        }, show_sprint, 'json');
   }
}

function create_sprint(result)
{
    data = result.data;
    if(result.errormsg != "")
    {
	alert(result.errormsg);
	return;
    }

    if (data.name)
    {
        var sprint_select_name = data.name;
        if (data.is_current)
        {
            sprint_select_name = '*'+sprint_select_name;
        }
        s_option = $('#selected_sprint option[value='+data.id+']');
        if (s_option.val())
        {
            s_option.text(sprint_select_name);
        } else
        { 
            $('#selected_sprint').children().each(function () { $(this).removeAttr('selected');});
            $('#selected_sprint option:last-child').before('<option value="'+data.id+'" selected="selected">'+sprint_select_name+'</option>');
        }
        show_sprint(result);
    } else {
        $('#selected_sprint option').each(function () { if ($(this).attr('selected')) { $(this).remove(); return false; };});
        $('#selected_sprint option').first().attr('selected', 'selected');
        get_sprint();
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

