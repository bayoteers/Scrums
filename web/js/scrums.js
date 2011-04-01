/*
 * Contributor(s):
 *   Visa Korhonen <visa.korhonen@symbio.com>
 */
// Eero's stuff

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
        }
    }).disableSelection();
}

function update_lists(bugs_list, move_pos, data, disabled) {
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

	if(disabled == true) {
            html += parseTemplate($("#DisabledLiTmpl").html(), {
                bug: bugs_list.list[bugs_list.visible[i]],
                counter: (bugs_list.visible[i] + 1)
            });
	}
	else {
	    html += parseTemplate($("#BugLiTmpl").html(), {
                bug: bugs_list.list[bugs_list.visible[i]],
                counter: (bugs_list.visible[i] + 1)
            });
	}
    }
    $("#" + bugs_list.ul_id).html(html);
}

function list_filter(header, list, bugs_list) { // header is any element, list is an unordered list
    // create and add the filter form to the header
    var form = $("<form>").attr({
        "class": "filterform",
        "action": "#"
    }),
        input = $("<input>").attr({
            "class": "filterinput",
            "type": "text"
        });
    //var html_obj = $(form).append(input)
    $(form).append(input).prependTo($(header).next());
    //$(header).next().after(html_obj);
    //html_obj.aft.appendTo(header);
    $(input).change(function() {
        var filter = $(this).val();
        if (filter) {
            bugs_list.visible = [];
            for (var i = 0; i < bugs_list.list.length; i++) {
                // search against desc and bug id
                if (bugs_list.list[i][3].toLowerCase().match("^" + filter.toLowerCase()) == filter.toLowerCase() || String(bugs_list.list[i][0]).match("^" + filter) == filter) {
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

//function init(schema, obj_id, lists) {
//    // DEMO
//    //var demo1 = new listObject("#demo1");
//    //var demo2 = new listObject("#demo2");
//
//    function call_back(data) {
//        for (var i = 0; i < lists.length; i++) {
//            update_lists(lists[i], 0, data[i]);
//            listFilter($(lists[i].h_id), $("#" + lists[i].ul_id), lists[i]);
//        }
//    }
//    $.post('page.cgi?id=scrums/ajax.html', {
//        schema: schema,
//        action: 'fetch',
//        obj_id: obj_id
//    }, call_back, 'json');
//    //update_lists(ordered_bugs);
//    bind_sortable_lists(lists);
//    // DEMO
//    //    update_lists(demo1);
//    //    update_lists(demo2);
//    //    listFilter($("#headers3"), $(demo1.ul_id), demo1);
//    //    listFilter($("#headers4"), $(demo2.ul_id), demo2);
//}

function move_list_left(list_id)
{
    move_list(list_id, -offset_step);
}
function move_list_right(list_id)
{
    move_list(list_id, offset_step);
}

function move_list(list_id, step)
{
    for (var i = 0; i< all_lists.length; i++)
    {
        if (all_lists[i].id == list_id)
        {
            update_lists(all_lists[i], step);
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
		alert("Success");
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
            data_lists[list_id].push(list.list[k][0]);
        }
    }

    function cb(data)
        {
        alert('jo');
            if (call_back != undefined)
            {
                call_back();
            }
        }

        
    $.post('page.cgi?id=scrums/ajax.html', {
        schema: schema,
        action: 'set',
        obj_id: obj_id,
        data: JSON.stringify(data_lists)
    }, saveResponse        , 'text');
//    }, saveResponse        , 'json');
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
            if (unordered_list.original_list[k][0] == unordered_list.list[i][0])
            {
                found = true;
                break;
            }
        }
            if (found != true)
            {
                // this bug is new in unordered list
                data_lists[list_id].push(unordered_list.list[i][0])
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
