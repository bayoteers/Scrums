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

function listObject(ul_id, h_id, id, name, li_tmpl) {
    this.ul_id = ul_id;
    this.id = id;
    this.h_id = h_id;
    this.list = [];
    this.orginal_list = [];
    this.visible = -1;
    this.offset = 0;
    this.offset_step = 99999; // default value
    this.name = name;
    this.li_tmpl = li_tmpl;
    this.show_columns = ['order', 'bug_id', 'points', 'summary'];
    this.show_priority = true;
    this.show_creation_date = false;
    this.show_severity = false;

    this.estimatedcapacity = null;
    this.personcapacity = null;
    this.pred_estimate = "-";
    this.history = "";
}

var from_list_ul_id = '';

function select_step(list_id)
{
    var sel = document.getElementById(list_id);
    var val = new Number(sel.value); // Val becomes 0, if sel.value equals "all"

    for (var i = 0; i< all_lists.length; i++)
    {
        if (all_lists[i].id == list_id)
        {
	    if(sel.value == "all")
	    {
	    	val = all_lists[i].length;
		all_lists[i].offset = 0;
	    }
	    all_lists[i].offset_step = val;
	    all_lists[i].visible = -1;
	    update_lists(all_lists[i]);
            break;
        }
    }
}

function switch_lists(ui, lists) {
    to_list_ul_id = ui.item.parent().attr('id');
    old_position = parseInt(ui.item.find('span.number').text() - 1);
    old_vis_position = parseInt(ui.item.attr('bug_order_nr'));
    to_list = undefined;
    from_list = undefined;
    var new_entry_id = '';
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
    $("#" + to_list.ul_id).find('tr').each(function(i) {
    //$("#" + to_list.ul_id).find('li').each(function(i) {
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
            new_entry_id = $(this).attr('id');
            new_position = order;
            var temp = from_list.list.splice(old_position, 1);
            to_list.list.splice(new_position, 0, temp[0]);
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
    if (new_entry_id)
    {
        $('#'+new_entry_id).children().each(function ()
        {
            $(this).effect( 'highlight', {color: '#404d6c'}, 1000 );
        });
    }

}

function bind_sortable_lists(lists) {
    // DEMO
    //$( "#sortable1, #sortable2, #demo1, #demo2"  ).sortable({
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
            switch_lists(ui, lists);;
        },
        items: 'tr:not(.ignoresortable)',
        helper: function(event , item)
        {
            return item.clone().attr('class', 'helper');
        },
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
        bugs_list.offset = bugs_list.visible.length - (bugs_list.visible.length % bugs_list.offset_step);
    }
    if (bugs_list.offset >= bugs_list.visible.length) {
        bugs_list.offset = 0;
    }
    html = "";
    //for(var i = bugs_list.offset; i < bugs_list.list.length; i++) {
    for (var i = bugs_list.offset; i < bugs_list.visible.length; i++) {
        if (i > bugs_list.offset + bugs_list.offset_step - 1) {
            break;
        }

    var template;
    if(bugs_list.li_tmpl) {
        template = bugs_list.li_tmpl
    }
    else {
        template = $("#BugLiTmpl");
    } 

    html += parseTemplate(template.html(),
    {
        bug: bugs_list.list[bugs_list.visible[i]],
        counter: (bugs_list.visible[i] + 1),
        show_columns: bugs_list.show_columns,
    });

    } // for
    if (html)
    {
        $("#" + bugs_list.ul_id).html(html);
    } else
    {
        $("#" + bugs_list.ul_id).html('<tr><td colspan="6">&nbsp;</td></tr><tr class="ignoresortable"><td colspan="6" align="center">No Items</td></tr>');
    }
    $("#table"+bugs_list.ul_id).tablesorter();
    //$("#table"+bugs_list.ul_id).tablesorter({locale: 'de', useUI: false});
    $('#items_' + bugs_list.id).html(bugs_list.list.length);
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
        
    //var html_obj = $(form).append(input)
    $(form).append('Filter: ').prependTo($(header).next());
    $(form).append(input).prependTo($(header).next());

    //$(header).next().after(html_obj);
    //html_obj.aft.appendTo(header);
    $(input).change(function() {
        var filter = $(this).val();
        if (filter) {
            bugs_list.visible = [];
            for (var i = 0; i < bugs_list.list.length; i++) {
                // search against desc and bug id
                var rg = new RegExp(filter,'i');
                // summary, assigned to and bug id
                if (bugs_list.list[i][5].search(rg) >= 0 || bugs_list.list[i][3].search(rg) >= 0 || String(bugs_list.list[i][0]).match("^" + filter) == filter) {
                //if (bugs_list.list[i][5].toLowerCase().match("^" + filter.toLowerCase()) == filter.toLowerCase() || String(bugs_list.list[i][0]).match("^" + filter) == filter) {
                    //filtered_bugs.list.push(bugs_list.list[i]);
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
		alert("There are errors: "+retObj.errormsg);
	}
	else
	{
		//alert("Success");
	}
}


function save(lists, schema, obj_id, data_lists, call_back) {
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

    $.post('page.cgi?id=scrums/ajax.html', {
        schema: schema,
        action: 'set',
        obj_id: obj_id,
        data: JSON.stringify(data_lists)
    }, saveResponse        , 'text');
}

function show_sprint(data)
{
    var sprint = new listObject("sortable", "headers", data.id, 'Sprint '+data.name, $("#TeamBugLiTmpl"));
    sprint._status = data._status;
    sprint.nominal_schedule = data.nominal_schedule;
    sprint.description = data.description;
    sprint.start_date = data.start_date;
    sprint.end_date = data.end_date;

    sprint.estimatedcapacity = data.estimatedcapacity
    sprint.personcapacity = data.personcapacity
    sprint.pred_estimate = data.prediction;
    sprint.history = data.history;

    $('#sprint_info').html(sprint.start_date+' - '+sprint.end_date+"<br /><input type='button' value='Edit Sprint' onClick='edit_sprint();'/>");
    $('#sprint').html(parseTemplate($('#ListTmpl').html(), { list: sprint, extra_middle: '' }));
    update_lists(sprint, 0, data.bugs);

    $('#unordered').html(parseTemplate($('#ListTmpl').html(), { list: backlog, extra_middle: '' }));
    update_lists(backlog, 0, backlog_bugs);
    all_lists = [sprint, backlog];
    bind_sortable_lists(all_lists);
}

function edit_sprint()
{

    sprint = all_lists[0];
    $('#sprint').html(parseTemplate($('#NewSprintTmpl').html(), { list: sprint, edit: true, sprintid: sprint.id }));
    $("input[name=sprintname]").val(sprint.name.replace('Sprint ', ''));
    $("input[name=nominalschedule]").val(sprint.nominal_schedule);
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
        var nominal_date = "";

        $("#datepicker_min").datepicker({ dateFormat: 'yy-mm-dd' });
        $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
        $("#datepicker_nominal").datepicker({ dateFormat: 'yy-mm-dd' });

}

        function archive()
        {
        gettime();
        if(range_end == "")
        {
            alert("End date is empty. Archived sprint must be stopped before archiving.");
            return false;
        }
        if(range_begin == "")
        {
            alert("Sprint start date is empty");
            return false;
        }

        return confirm("Are you sure you want to archive sprint '[% sprintname %]'?");
        }

        function cancel()
        {
        window.location = "page.cgi?id=scrums/teambugs2.html&teamid=[% teamid %]";  
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

        if(nominal_date == "")
        {
          alert("Sprint must have nominal schedule.");
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
            nominal_date = $('#datepicker_nominal').val();
        }



function get_sprint()
{
    if ($('#selected_sprint').val() == 'new_sprint')
    {


        $('#sprint_info').html('Create new sprint');
        $('#sprint').html(parseTemplate($('#NewSprintTmpl').html(), { list: sprint, edit: false, sprintid: 0 }));
        var options = { 
            success:   create_sprint,
            dataType: 'json'
            } 
        $('#new_sprint_form').ajaxForm(options);

        var range_begin = "";
        var range_end = "";
        var nominal_date = "";

        $("#datepicker_min").datepicker({ dateFormat: 'yy-mm-dd' });
        $("#datepicker_max").datepicker({ dateFormat: 'yy-mm-dd' });
        $("#datepicker_nominal").datepicker({ dateFormat: 'yy-mm-dd' });


    } else
    {
        $.post('page.cgi?id=scrums/ajaxsprintbugs.html', {
            teamid: team_id,
            sprintid: $('#selected_sprint').val(),
        }, show_sprint, 'json');
    }
}

function create_sprint(data)
{
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
        show_sprint(data);
    } else {
        $('#selected_sprint option').each(function () { if ($(this).attr('selected')) { $(this).remove(); return false; };});
        $('#selected_sprint option').first().attr('selected', 'selected');
        get_sprint();
    }
}



function save_lists(ordered_lists, unordered_list, schema, obj_id, call_back)
{
    // need to use Object instead of Array when ajaxing an associative array
    var data_lists = new Object();
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
    save(ordered_lists, schema, obj_id, data_lists, call_back);
    unordered_list.original_list = $.extend(true, [], unordered_list.list);
}

// le template engine
var _tmplCache = {}
this.parseTemplate = function(str, data) {
    /// <summary>                                                                                                           
    /// Client side template parser that uses &lt;#= #&gt; and &lt;# code #&gt; expressions.                                
    /// and # # code blocks for template expansion.                                                                         
    /// NOTE: chokes on single quotes in the document in some situations                                                    
    ///       use &amp;rsquo; for literals in text and avoid any single quote                                               
    ///       attribute delimiters.                                                                                         
    /// </summary>                                                                                                          
    /// <param name="str" type="string">The text of the template to expand</param>                                          
    /// <param name="data" type="var">                                                                                      
    /// Any data that is to be merged. Pass an object and                                                                   
    /// that object's properties are visible as variables.                                                                  
    /// </param>                                                                                                            
    /// <returns type="string" />                                                                                           
    var err = "";
    try {
        var func = _tmplCache[str];
        if (!func) {
            var strFunc = "var p=[],print=function(){p.push.apply(p,arguments);};" + "with(obj){p.push('" + str.replace(/[\r\t\n]/g, " ").replace(/'(?=[^#]*#>)/g, "\t").split("'").join("\\'").split("\t").join("'").replace(/<#=(.+?)#>/g, "',$1,'").split("<#").join("');").split("#>").join("p.push('") + "');}return p.join('');";
            //alert(strFunc);                                                                                               
            func = new Function("obj", strFunc);
            _tmplCache[str] = func;
        }
        return func(data);
    } catch (e) {
        err = e.message;
    }
    return "< # ERROR: " + err + " # >";
    //return "< # ERROR: " + err.htmlEncode() + " # >";                                                                     
}
