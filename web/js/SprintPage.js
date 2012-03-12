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
  *   David Wilson <dw@botanicus.net>
  */


/**
 * Callback (pointlessly) invoked by detect_unsaved_change(); expected to
 * somehow save unsaved changes during window destruction.
 */
function save_all()
{
  do_save(/* scrums.js */ all_lists);
}


/**
 * Utility functions for manipulating Date objects.
 */
var DateUtil = {
    /**
     * Return a Date object representing the current time on the next business day
     * (e.g. on 3:41pm on a Friday, return 3:41pm on the following Monday).
     */
    getNextBusinessDay: function()
    {
        var now = (new Date()).getTime();
        do {
            now += 86400 * 1000;
            var cur = new Date(now);
        } while(! (cur.getDay() >= 1 && cur.getDay() <= 5));
        return cur;
    },

    /**
     * Add some milliseconds to a Date object.
     */
    add: function(dt, ms)
    {
        return new Date(dt.getTime() + ms);
    },

    /**
     * Right justify the string `s` to width `n` using character `c`.
     */
    lpad: function(s, n, c)
    {
        s = '' + s;
        n = n || 2;
        c = c || '0';
        while(s.length < n) {
            s = c + s;
        }
        return s;
    },

    /**
     * Given a Date object, return a string "YYYY-MM-DD".
     */
    isoFormat: function(dt)
    {
        var lpad = this.lpad;
        return [lpad(dt.getYear() + 1900),
                lpad(1 + dt.getMonth()),
                lpad(dt.getDate())].join('-');
    }
};


/**
 * Display a form to create or edit a sprint.
 */
var SprintEditor = {
    /**
     * Reinitialize the object, recreating the editor form using the associated
     * template.
     *
     * @param sprint
     *      If given, the sprint object we're editing. Otherwise, render the
     *      "Create Sprint" form instead.
     */
    _init: function(sprint)
    {
        var form = $("#sprint_editor_template").clone();
        this.state = {
            form: form,
            sprint: sprint
        };

        form.ajaxForm({
            success: this._onCreateDone.bind(this),
            dataType: 'json'
        });

        function append(name, value) {
            $('<input>').attr({
                name: name,
                value: value,
                type: 'hidden'
            }).appendTo(form);
        }

        append('teamid', SCRUMS_CONFIG.team.id);

        if(sprint) {
            append('schema', 'editsprint');
            append('sprintid', sprint.id);
            $('.save-buttons', form).remove();
            $('h3', form).text('Edit Sprint');
        } else {
            append('schema', 'newsprint');
            $('.edit-buttons', form).remove();
            $('h3', form).text('Create Sprint');
        }

        this._field('start_date').datepicker({
            minDate: new Date(),
            dateFormat: 'yy-mm-dd'
        });
        this._field('start_date').change(this._onStartDateChange.bind(this));

        this._field('end_date').datepicker({
            dateFormat: 'yy-mm-dd'
        });

        this._child('.cancelEdit').click(this._onCancelClick.bind(this));
        this._child('.cancelEdit').toggle(!!SCRUMS_CONFIG.active_sprint);
        $('#sprint').html(form);
    },

    /**
     * Handle the start date changing by updating the end date automatically.
     */
    _onStartDateChange: function()
    {
        var days = SCRUMS_CONFIG.default_sprint_days;
        var startDate = this._field('start_date').datepicker('getDate');
        var endDate = DateUtil.add(startDate, days * 86400 * 1000);
        this._field('end_date').val(DateUtil.isoFormat(endDate));
    },

    /**
     * Handle user clicking cancel by re-rendering the sprint bugs list.
     */
    _onCancelClick: function()
    {
        $('select[name=sprintid]').get(0).selectedIndex = 0;
        this.close();
        SprintView.refreshSprint();
    },

    /**
     * Return a jQuery object containing children matching the given selector.
     */
    _child: function(sel)
    {
        return $(sel, this.state.form);
    },

    /**
     * Return a jQuery object containing the form input with the given name.
     */
    _field: function(name)
    {
        return $('input[name=' + name + ']', this.state.form);
    },

    /**
     * Respond to the create button being clicked by validating the form then
     * appending the 'move bugs' hidden field.
     */
    _onCreateClick: function()
    {
        if(! this.validate()) {
            return false;
        }

        if(confirm('Move open bugs from previous sprint into new sprint?')) {
            this._field('takebugs').val('true');
        }

        return true;
    },

    /**
     * Open a form to edit an existing sprint.
     */
    openEdit: function(sprint)
    {
        this.close();
        this._init(sprint);

        this._field('sprintname').val(sprint.name.replace('Sprint ', ''));
        this._field('description').val(sprint.description);
        this._field('start_date').val(sprint.start_date);
        this._field('end_date').val(sprint.end_date);
        this._field('submit').val('Save');
        this._field('estimatedcapacity').val(sprint.estimatedcapacity);
        this._child('.personcapacity').html(sprint.personcapacity);
        this._child('.sprint-estimate').html(sprint.prediction);
        this._child('.sprint-history').html(sprint.history);

        this._field('editsprint').click(this._onSaveClick.bind(this));
        this._field('deletesprint').click(this._onDeleteClick.bind(this));
    },

    /**
     * Handle user clicking Save by validating the form.
     */
    _onSaveClick: function()
    {
        return this.validate();
    },

    /**
     * Handle user clicking delete by displaying a confirmation.
     */
    _onDeleteClick: function()
    {
        return confirm('Are you sure you want to delete this sprint?');
    },

    /**
     * Hide any active form, discarding any changes.
     */
    close: function()
    {
        if(this.state) {
            this.state.form.remove();
            this.state = null;
        }
    },

    /**
     * Validate the form contents prior to submission.
     */
    validate: function()
    {
        var name = this._field('sprintname').val();
        if(! name) {
            alert("Sprint must have name.");
            return false;
        } else if(! name.match(/^\S/)) {
            alert("Sprint name can not start with whitespace");
            return false;
        }

        if(! this._field('start_date').val()) {
            alert("Missing start date");
            return false;
        } else if(! this._field('end_date').val()) {
            alert("Missing end date");
            return false;
        }

        return true;
    },

    /**
     * Open the editor, populating a new sprint.
     */
    openCreate: function()
    {
        this.close();
        this._init();

        var startDate = DateUtil.getNextBusinessDay();
        var days = SCRUMS_CONFIG.default_sprint_days;
        var endDate = DateUtil.add(startDate, days * 86400 * 1000);

        this._field('start_date').val(DateUtil.isoFormat(startDate));
        this._field('end_date').val(DateUtil.isoFormat(endDate));
        this._child('.sprint-history').html(SprintView.makeSprintHistory());
        this._field('newsprint').click(this._onCreateClick.bind(this));
    },

    _onCreateDone: function(result)
    {
        if(result.errormsg) {
            alert(result.errormsg);
            return;
        }
        window.location.reload();
    }
};


/**
 * Display an inline editor for updating a team member's capacity estimate for
 * the current sprint.
 */
var MemberCapacityEditor = {
    /**
     * Open the editor for the given team member ID (aka. profile ID).
     */
    open: function(id) {
        if(! this.close(true)) {
            return;
        }

        this.state = {
            id: id,
            staticEl: $('#' + id + '_static'),
            editableEl: $('#' + id + '_editable'),
            select: $('#' + id + '_editable select')
        };

        this.state.oldValue = $.trim($('.value', this.state.staticEl).text());
        this.state.select.val(this.state.oldValue);
        this.state.staticEl.css('visibility', 'collapse');
        this.state.editableEl.css('visibility', 'visible');
    },

    /**
     * Make static field visible and make editable field hidden
     */
    close: function(doConfirm)
    {
        if(! this.state) {
            return true;
        }

        var dirty = this.state.select.val() != this.state.oldValue;
        if(dirty && doConfirm && !confirm("Discard changes?")) {
            return false;
        }

        $('.value', this.state.staticEl).text(this.state.select.val());
        this.state.staticEl.css('visibility', 'visible');
        this.state.editableEl.css('visibility', 'collapse');
        this.state = null;
    },

    /**
     * Save value of one bug field into database by doing AJAX-call.
     */
    save: function()
    {
        $.post('page.cgi?id=scrums/ajax.html', {
            schema: 'personcapacity',
            action: 'update',
            data: JSON.stringify({
                method: 'personcapacity.update',
                params: {
                    sprint_id: SCRUMS_CONFIG.active_sprint.id,
                    person_id: this.state.id,
                    capacity: this.state.select.val()
                }
            })
        }, this._onSaveDone.bind(this), 'text');
    },

    /**
     * Callback fired after succesful AJAX call returns. AJAX call if
     * succesful, if server responds without throwing exception. Ordered errors
     * are shown in error message. Function shows status of saving to user.
     */
    _onSaveDone: function(response, status, xhr)
    {
        var retObj = $.parseJSON(response);
        if(retObj.errors) {
            alert(retObj.errormsg);
        } else {
            this.close();
        }
    }
};


/**
 * Main implementation for 'sprint view', i.e. teambugs.html.tmpl.
 */
var SprintView = {
    /**
     * Initialize the object, installing any global variables required by
     * scrums.js.
     */
    init: function()
    {
        /** These must be true before _updateReady will render bug lists. */
        this._sprintReady = false;
        this._backlogReady = false;
        this._sprintInfoReady = false;

        /* scrums.js */ sprint_callback = this._updateBugCapacity.bind(this);
        /* scrums.js */ update_tables = this._updateTables.bind(this);
        /* scrums.js */ schema = 'sprint';
        /* scrums.js */ object_id = SCRUMS_CONFIG.team.id;

        /** listObject containing bugs assigned to the current sprint. */
        this.sprint = this._makeSprintList();
        /** listObject containing bugs in the team's backlog. */
        this.backlog = this._makeBacklogList();

        // Notice! Lists must be in this order. They are also saved in that
        // order. Mixing them spoils team order values.
        /* scrums.js */ all_lists = [this.sprint, this.backlog];
    },

    /**
     * Start refreshing metadata for the selected sprint, or, if "new sprint"
     * is selected, display the Create Sprint form instead.
     */
    refreshSprint: function()
    {
        var sprintId = $('#selected_sprint').val();
        if (sprintId == 'new_sprint') {
            SprintEditor.openCreate();
        } else {
            $.post('page.cgi?id=scrums/ajaxsprintbugs.html', {
                teamid: SCRUMS_CONFIG.team.id,
                sprintid: sprintId
            }, this._onRefreshSprintDone.bind(this), 'json');
        }
    },

    /**
     * Respond to completion of metadata refresh by updating the sprint
     * listObject and triggering _checkReady().
     *
     * @param result
     *      JSON result object.
     */
    _onRefreshSprintDone: function(result)
    {
        if(result.errormsg) {
            alert(result.errormsg);
            return;
        }

        var keys = ['_status', 'description', 'start_date', 'end_date',
            'estimatedcapacity', 'personcapacity', 'prediction', 'history'];
        for(var i = 0; i < keys.length; i++) {
            this.sprint[keys[i]] = result.data[keys[i]];
        }

        $('#sprint_info').html(this.sprint.start_date + ' &mdash; ' +
            this.sprint.end_date);
        $('#editSprintButton').click(this._onEditSprintClick.bind(this));

        this._sprintInfoReady = true;
        this._checkReady();
    },

    /**
     * Respond to Edit Sprint being clicked by opening the sprint editor.
     */
    _onEditSprintClick: function()
    {
        SprintEditor.openEdit(this.sprint);
    },

    /**
     * Invoked by scrums.js::switch_lists() to indicate a bug has been moved
     * from one listObject to another listObject.
     *
     * Walk the bugs in priority order that are scheduled for this sprint, then
     * the bugs still in the backlog, flagging each according to whether its
     * work estimate fits within the resource limits of the sprint.
     *
     * The updated flag ("row[10]") is later used by ListHtmlTempl.js to paint
     * bug rows a different colour to indicate those that are overcapacity.
     */
    _updateBugCapacity: function()
    {
        var that = this;
        var cum = 0;

        function update(_, row)
        {
            cum += row[9];
            row[10] = +(cum <= that.sprint.estimatedcapacity);
        }

        $.each(this.sprint.list, update);
        $.each(this.backlog.list, update);
        this._updateSprintStats();
    },

    /**
     * Update the UI total/done/remaining work totals using the sprint
     * listObject's bugs list.
     */
    _updateSprintStats: function()
    {
        var sprint_total_work = 0;
        var sprint_done_work = 0;
        var sprint_remaining_work = 0;

        $.each(this.sprint.list, function(_, row)
        {
            sprint_remaining_work += row[1];
            sprint_done_work += row[8];
            sprint_total_work += row[9];
        });

        $('#capa').html(this.sprint.estimatedcapacity);
        $('#free').html(this.sprint.estimatedcapacity - sprint_total_work);
        $('#done').html(sprint_done_work);
        $('#remaining').html(sprint_remaining_work);
    },

    /**
     * Render the team's sprint history as an HTML table and return it as a
     * string. If no history was provided by the backend, return the empty
     * string.
     */
    makeSprintHistory: function()
    {
        if(! SCRUMS_CONFIG.sprint_history) {
            return '';
        }

        var bits = ['<table>'];
        for(var i = 0; i < SCRUMS_CONFIG.history.length; i++) {
            var item = SCRUMS_CONFIG.history[i];
            bits.push('<tr>');
            bits.push('<th>' + item.name + '</th>');
            bits.push("<td style='min-width: 110px;'>" +
                'Total Work: ' + item.total_work + '</td>');
            bits.push('<td>Total Persons: ' + item.total_persons + '</td>');
            bits.push('</tr>');
        }
        bits.push('</table>');
        return bits.join('\n');
    },

    /**
     * Temporarily required to act like the old JS did, ie. paper over bugs
     * when various values weren't passed in from the template.
     */
    _makeSprintList: function()
    {
        var id;
        if(SCRUMS_CONFIG.active_sprint) {
            id = SCRUMS_CONFIG.active_sprint.id;
        }

        var name = id ? SCRUMS_CONFIG.active_sprint.name : '';
        var url = search_link_sprint_items(id);
        var lst = new listObject("sortable", "headers", id, 'Sprint ' + name,
            create_item_line_html, url);

        lst._status = id ? SCRUMS_CONFIG.active_sprint.status : '';
        lst.estimatedcapacity = null;
        lst.personcapacity = null;
        lst.prediction = "-";
        lst.description = id ? SCRUMS_CONFIG.active_sprint.description : '';
        lst.history = this.makeSprintHistory();
        return lst;
    },

    /**
     * Start refreshing the list of bugs already associated with the current
     * sprint, or if there is no current sprint, immediately bind an empty list to
     * the sprint listObject.
     */
    refreshSprintBugs: function()
    {
        if(SCRUMS_CONFIG.active_sprint) {
            $.post('page.cgi?id=scrums/ajaxbuglist.html', {
                sprint_id: SCRUMS_CONFIG.active_sprint.id
            }, this._onRefreshSprintBugsDone.bind(this), 'json');
        } else {
            bind_items_to_list(this.sprint, []);
            this._sprintReady = true;
        }
    },

    /**
     * Respond to completion of refreshSprintBugs() by binding the received
     * list to the sprint listObject and triggering _checkReady().
     */
    _onRefreshSprintBugsDone: function(result)
    {
        bind_items_to_list(this.sprint, result.data.bugs);
        this._sprintReady = true;
        this._checkReady();
    },

    /**
     * Return a listObject to represent the sprint backlog.
     */
    _makeBacklogList: function()
    {
        var id = SCRUMS_CONFIG.backlog_id;
        var title;
        var url;

        if(id) {
            title = 'Backlog';
            url = search_link_sprint_items(id);
        } else {
            // When all items are shown as 'backlog' to user, backlog must have
            // sprint id of unprioritised items. This is important because all its
            // items are saved as actual backlog otherwise.
            id = '-1';
            title = 'Backlog (all items)';
            url = makeUrl('buglist.cgi', {
                query_format: 'advanced',
                columnlist: SCRUMS_SEARCH_COLUMN_LIST.join(','),
                bug_status: SCRUMS_CONFIG.bug_status_open,
                classification: SCRUMS_CONFIG.classifications,
                product: SCRUMS_CONFIG.products,
                component: SCRUMS_CONFIG.components
            });
        }

        return new listObject("sortable2", "headers2", id,
            title, create_item_line_html, url);
    },

    /**
     * Start refreshing the list of bugs in the team's backlog, or if the team
     * has no backlog, the list of unassigned bugs in any of the components for
     * which the team is responsible.
     */
    refreshBacklog: function()
    {
        var params;
        if(SCRUMS_CONFIG.team.is_using_backlog) {
            params = {
                sprint_id: SCRUMS_CONFIG.team.backlog_id
            };
        } else {
            params = {
                action: "other_items_than_in_active_sprint",
                team_id: SCRUMS_CONFIG.team.id
            };
        }

        $.post('page.cgi?id=scrums/ajaxbuglist.html', params,
            this._onRefreshBacklogDone.bind(this), 'json');
    },

    /**
     * Respond to completion of the refreshBacklog() request by binding the
     * received list to the backlogs listObject.
     */
    _onRefreshBacklogDone: function(result)
    {
        bind_items_to_list(this.backlog, result.data.bugs);
        this._backlogReady = true;
        this._checkReady();
    },

    /**
     * Delay rendering of the bug list tables until all of the sprint bug list,
     * sprint metadata, and backlog bug list data is available.
     *
     * If there is no active sprint, then render_all() is never called. This
     * prevents the bug lists appearing when there is no sprint to add bugs to.
     */
    _checkReady: function()
    {
        if(this._backlogReady && this._sprintReady &&
                this._sprintInfoReady) {
            /* scrums.js */ render_all();
            /* scrums.js */ toggle_scroll();
        }
    },

    /**
     * Callback invoked by scrums.js::render_all().
     */
    _updateTables: function()
    {
        this._updateBugCapacity();
        /* scrums.js */ update_lists(this.sprint, 0);
        /* scrums.js */ update_lists(this.backlog, 0);
        // Does not initialise tablesorter
        /* scrums.js */ bind_sortable_lists(all_lists);
    }
};


/**
 * Main script implementation. Prepare sprint and backlog list objects, then
 * refreshing them along with the sprint metadata.
 */
function onDocumentReady()
{
    SprintView.init();

    SprintView.refreshSprint();
    if(SCRUMS_CONFIG.active_sprint) {
        SprintView.refreshSprintBugs();
        SprintView.refreshBacklog();
    }

    window.onbeforeunload = detect_unsaved_change;
}

$(document).ready(onDocumentReady);
