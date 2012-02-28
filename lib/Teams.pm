# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Scrums Bugzilla Extension.
#
# The Initial Developer of the Original Code is "Nokia corporation"
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

package Bugzilla::Extension::Scrums::Teams;

use Bugzilla::Extension::Scrums::Team;
use Bugzilla::Extension::Scrums::Sprint;
use Bugzilla::Extension::Scrums::Sprintslib;
use Bugzilla::Extension::Scrums::Teamorderlib;

use Bugzilla::Util qw(trick_taint);
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Component;

use JSON::PP;

use strict;
use base qw(Exporter);
our @EXPORT = qw(

  show_all_teams
  show_create_team
  add_into_team
  search_person
  edit_team
  show_team_bugs
  show_products
  update_team_bugs
  move_pending_items
  );

# This file can be loaded by your extension via
# "use Bugzilla::Extension::PMO::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub show_all_teams($) {
    my ($vars) = @_;

    my $cgi         = Bugzilla->cgi;
    my $delete_team = $cgi->param('deleteteam');
    if ($delete_team && $delete_team ne "") {
        if (not Bugzilla->user->in_group('admin')) {
            ThrowUserError('auth_failure', { group => "admin", action => "delete", object => "team" });
        }
        _delete_team($delete_team);
    }

    my $sort = $cgi->param('sort');

    if (!$sort) {
        # Set default sort to be by name.
        $sort = 1;
    }

    my $team_list = Bugzilla::Extension::Scrums::Team->all_teams($sort);

    $vars->{'sort'}     = $sort;
    $vars->{'teamlist'} = $team_list;
}

sub _delete_team {
    my ($team_id) = @_;

    if ($team_id =~ /^([0-9]+)$/) {
        $team_id = $1;    # $data now untainted
        my $team = Bugzilla::Extension::Scrums::Team->new($team_id);

        my $sprints = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $team_id, item_type => 1 });
        for my $sprint (@{$sprints}) {
            if (!$sprint->end_date()) {
                ThrowUserError('team_has_active_sprint', {});
            }
            use Time::Local;
            my $now = time;
            my ($yyyy, $mm, $dd);
            ($yyyy, $mm, $dd) = ($sprint->end_date() =~ /(\d+)-(\d+)-(\d+)/);
            my $edate = timelocal(0, 0, 0, $dd, $mm - 1, $yyyy);
            if ($now <= $edate) {
                ThrowUserError('team_has_active_sprint', {});
            }
        }

        my $components = $team->components();
        if (scalar @{$components} > 0) {
            ThrowUserError('team_has_components', {});
        }

        # There is always a backlog
        my $backlog = $team->get_team_backlog();
        $backlog->remove_from_db();

        $team->remove_from_db();
    }
}

sub show_create_team {
    my ($vars) = @_;

    my $error   = "";
    my $cgi     = Bugzilla->cgi;
    my $team_id = $cgi->param('teamid');

    if ($team_id ne "") {
        if ($team_id =~ /^([0-9]+)$/) {
            $team_id = $1;    # $data now untainted
            my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
            if ($cgi->param('removedcomponent') && $cgi->param('removedcomponent') ne "") {
                if (not Bugzilla->user->in_group('scrums_editteams')) {
                    ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
                }
                my $component_id = $cgi->param('removedcomponent');
                if ($component_id =~ /^([0-9]+)$/) {
                    $component_id = $1;
                    # This removes component from this team.
                    $team->remove_component($component_id);
                }
            }
            if ($cgi->param('component') && $cgi->param('component') ne "") {
                if (not Bugzilla->user->in_group('scrums_editteams')) {
                    ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
                }
                my $component_id = $cgi->param('component');
                if ($component_id =~ /^([0-9]+)$/) {
                    $component_id = $1;
                    # This removes component from any old team, if there was one.
                    $team->remove_component($component_id);
                    # This adds component into 'this' team.
                    $team->set_component($component_id);
                }
            }
            if ($cgi->param('editteam') && $cgi->param('editteam') ne "") {
                if (not Bugzilla->user->in_group('scrums_editteams')) {
                    ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
                }
                my $team_name        = $cgi->param('name');
                my $team_owner       = $cgi->param('userid');
                my $scrum_master     = $cgi->param('scrummasterid');
                my $is_using_backlog = $cgi->param('usesbacklog');
                if ($team_owner =~ /^([0-9]+)$/) {
                    $team_owner = $1;                                                                          # $data now untainted
                    $error = _update_team($team, $team_name, $team_owner, $scrum_master, $is_using_backlog);
                    if ($error ne "") {
                        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => $error });
                    }
                }
                else {
                    ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => " Illegal team owner" });
                }
            }
            _show_existing_team($vars, $team);
        }
        else {
            ThrowUserError('scrums_team_not_found');
        }
    }
    else {
        if (not Bugzilla->user->in_group('scrums_editteams')) {
            ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
        }
        _new_team($vars);
    }
}

sub _show_existing_team {
    my ($vars, $team) = @_;

    my $cgi = Bugzilla->cgi;

    my $user_id = 0;
    if ($cgi->param('userid')) {
        $user_id = $cgi->param('userid');
    }

    if ($user_id ne "") {
        if (not Bugzilla->user->in_group('scrums_editteams')) {
            ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
        }
        if ($user_id =~ /^([0-9]+)$/) {
            $user_id = $1;    # $data now untainted
            if ($cgi->param('addintoteam') && $cgi->param('addintoteam') ne "") {
                $team->set_member($user_id);
            }
            else {
                $team->remove_member($user_id);
            }
        }
    }
    $vars->{'team'} = $team;
    my $sprints = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $team->id(), item_type => 1 });
    if (@{$sprints}) {
        my $last = pop(@{$sprints});
        $vars->{'active_sprint'}      = $last;
        $vars->{'active_sprint_id'}   = $last->id();
        $vars->{'active_sprint_name'} = $last->name();
    }
}

sub _new_team {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;

    my $name         = $cgi->param('name');
    my $owner_id     = $cgi->param('userid');
    my $scrum_master = $cgi->param('scrummasterid');

    my $error = "";
    if ($name =~ /^([-\ \w]+)$/) {
        $name = $1;    # $data now untainted
    }
    else {
        $error = " Illegal name";
        $name  = "";
    }

    if ($owner_id =~ /^([-\ \w]+)$/) {
        $owner_id = $1;    # $data now untainted
    }
    else {
        $error .= " Illegal owner";
        $owner_id = "";
    }

    if ($scrum_master =~ /^([-\ \w]+)$/) {
        $scrum_master = $1;    # $data now untainted
    }
    else {
        $scrum_master = "";
    }

    if ($name and $owner_id) {
        my $team;
        if ($scrum_master) {
            $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner_id, scrum_master => $scrum_master });
        }
        else {
            $team = Bugzilla::Extension::Scrums::Team->create({ name => $name, owner => $owner_id });
        }
        my $new_id = $team->id();
        my $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                                                          {
                                                            team_id     => $new_id,
                                                            status      => "NEW",
                                                            item_type   => 2,
                                                            name        => "Product backlog",
                                                            description => "This is automatically generated static 'sprint' for the purpose of product backlog"
                                                          }
        );
        _show_existing_team($vars, $team);
    }
    else {
        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => $error });
    }

    $vars->{'teamisnew'} = "true";
}

sub add_into_team {
    my ($vars) = @_;

    my $cgi     = Bugzilla->cgi;
    my $user_id = $cgi->param('userid');
    my $team_id = $cgi->param('teamid');

    if ($team_id ne "") {
        if ($team_id =~ /^([0-9]+)$/) {
            $team_id = $1;    # $data now untainted
        }
        else {
            ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => " Illegal team id" });
        }
    }

    if ($user_id ne "") {
        if ($user_id =~ /^([0-9]+)$/) {
            $user_id = $1;    # $data now untainted

            $vars->{'userid'}       = $user_id;
            $vars->{'userrealname'} = $cgi->param('userrealname');
            $vars->{'userlogin'}    = $cgi->param('userlogin');
            $vars->{'teamid'}       = $cgi->param('teamid');
            $vars->{'teamname'}     = $cgi->param('teamname');
        }
        else {
            ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => " Illegal user id" });
        }
    }
}

sub search_person {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;

    my $matchvalue = $cgi->param('matchvalue') || '';
    my $matchstr   = $cgi->param('matchstr');
    my $matchtype  = $cgi->param('matchtype');
    my $query      = 'SELECT DISTINCT userid, login_name, realname, disabledtext ' . 'FROM profiles WHERE';
    my @bindValues;
    my $nextCondition = "";

    # Handle selection by login name, real name, or userid.
    if (defined($matchtype)) {
        $query .= " $nextCondition ";
        my $expr = "";
        if ($matchvalue eq 'userid') {
            if ($matchstr) {
                my $stored_matchstr = $matchstr;
                detaint_natural($matchstr)
                  || ThrowUserError('illegal_user_id', { userid => $stored_matchstr });
            }
            $expr = "profiles.userid";
        }
        elsif ($matchvalue eq 'realname') {
            $expr = "profiles.realname";
        }
        else {
            $expr = "profiles.login_name";
        }

        if ($matchstr =~ /^(regexp|notregexp|exact)$/) {
            $matchstr ||= '.';
        }
        else {
            $matchstr = '' unless defined $matchstr;
        }
        # We can trick_taint because we use the value in a SELECT only,
        # using a placeholder.
        trick_taint($matchstr);

        if ($matchtype eq 'regexp') {
            $query .= $dbh->sql_regexp($expr, '?', 0, $dbh->quote($matchstr));
        }
        elsif ($matchtype eq 'notregexp') {
            $query .= $dbh->sql_not_regexp($expr, '?', 0, $dbh->quote($matchstr));
        }
        elsif ($matchtype eq 'exact') {
            $query .= $expr . ' = ?';
        }
        else {    # substr or unknown
            $query .= $dbh->sql_istrcmp($expr, '?', 'LIKE');
            $matchstr = "%$matchstr%";
        }
        $nextCondition = 'AND';
        push(@bindValues, $matchstr);

        $query .= ' ORDER BY profiles.login_name';

        $vars->{'query'} = $query;
        $vars->{'users'} = $dbh->selectall_arrayref($query, { 'Slice' => {} }, @bindValues);
    }

    $vars->{'formname'}        = $cgi->param('formname');
    $vars->{'formfieldprefix'} = $cgi->param('formfieldprefix');
    $vars->{'submit'}          = $cgi->param('submit');
}

sub edit_team {
    my ($vars) = @_;

    my $cgi      = Bugzilla->cgi;
    my $editteam = $cgi->param('editteam');
    if ($editteam eq "") {
        # If we are not editing existing team, we are creating new team. Check user access.
        if (not Bugzilla->user->in_group('admin')) {
            ThrowUserError('auth_failure', { group => "admin", action => "add", object => "team" });
        }
    }
    else {
        if (not Bugzilla->user->in_group('scrums_editteams')) {
            ThrowUserError('auth_failure', { group => "scrums_editteams", action => "edit", object => "team" });
        }
    }
    $vars->{'editteam'} = $editteam;
    my $team_id = $cgi->param('teamid');
    $vars->{'teamid'} = $team_id;
    if ($editteam ne "") {
        my $team = Bugzilla::Extension::Scrums::Team->new($team_id);
        $vars->{'team'} = $team;
    }
    $vars->{'realname'}             = $cgi->param('realname');
    $vars->{'loginname'}            = $cgi->param('loginname');
    $vars->{'scrummasterrealname'}  = $cgi->param('scrummasterrealname');
    $vars->{'scrummasterloginname'} = $cgi->param('scrummasterloginname');
}

# Show team bugs is a whole, which consists of team and active sprints of team
sub show_team_bugs {
    my ($vars) = @_;

    my $team_id = Bugzilla->cgi->param('teamid');
    my $sprint_id = Bugzilla->cgi->param('sprint_id');

    my $team    = Bugzilla::Extension::Scrums::Team->new($team_id);
    $vars->{'team'}               = $team;
    $vars->{'unprioritised_bugs'} = $team->unprioritised_bugs();

    my @team_sprints_array;
    my $capacity;

    my $sprint;
    if($sprint_id) {
        $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
        ThrowUserError('scrums_sprint_not_found') unless $sprint->{id};
    } else {
        $sprint = $team->get_team_current_sprint();
    }

    $vars->{'active_sprint'} = $sprint;

    if ($sprint) {
        $vars->{'capacity'} = $sprint->get_capacity_summary();

        # History information for *new* sprint
        my $pred_estimate = $sprint->get_predictive_estimate();
        $vars->{'history'} = $pred_estimate->{'history'};

        $vars->{'active_sprint_id'} = $sprint->id();
    }

    # There is always a backlog
    my $team_backlog = $team->get_team_backlog();
    $vars->{'backlog_id'} = $team_backlog->id();

    # Component, product and classification names are needed for creating bug lists, that have editable search
    my $components = $team->components();
    my @comp_names;
    my @prod_names;
    my @class_names;
    for my $comp (@{$components}) {
        my $co_name = $comp->name();
        if (!(grep { $_ eq $co_name } @comp_names)) {
            push @comp_names, $co_name;
        }
        my $prod   = $comp->product();
        my $p_name = $prod->name();
        if (!(grep { $_ eq $p_name } @prod_names)) {
            push @prod_names, $p_name;
        }
        my $c_id       = $prod->classification_id();
        my $class      = new Bugzilla::Classification($c_id);
        my $class_name = $class->name();
        if (!(grep { $_ eq $class_name } @class_names)) {
            push @class_names, $class_name;
        }
    }

    my $scrums_config = {
        default_sprint_days => Bugzilla->params->{'scrums_default_sprint_days'},
        team => {
            id => $team->id(),
            is_using_backlog => 0+$team->is_using_backlog(),
            backlog_id => $team_backlog->id(),
        },
        bug_status_open => [ Bugzilla::Status::BUG_STATE_OPEN() ],
        classifications => \@class_names,
        products => \@prod_names,
        components => \@comp_names,
    };

    if($sprint) {
        $scrums_config->{active_sprint} = {
            name => $sprint->name(),
            id => $sprint->id(),
            status => $sprint->status(),
            description => $sprint->description()
        };
    }

    if($vars->{sprint_history}) {
        $scrums_config->{sprint_history} = [ map { {
            name => $_->[0],
            total_work => $_->[1],
            total_persons => $_->[2]
        } } @{$vars->{history} ? $vars->{history} : []} ];
    }

    $vars->{scrums_config} = JSON->new->utf8->pretty->encode($scrums_config);
}

sub show_products {
    my ($vars, $teams) = @_;

    my @user_products;
    for my $team (@{$teams}) {
        my $components = $team->components();
        for my $component (@{$components}) {

            my $product       = $component->product();
            my $class_id      = $product->classification_id();
            my $class         = Bugzilla::Classification->new($class_id);
            my $complete_name = "\"" . $team->name() . "\" - " . $class->name() . " - " . $product->name() . "/" . $component->name();
            my $product_name  = $product->name();
            my $component_name  = $component->name();
            my @item          = ($product_name, $component_name, $complete_name);
            push(@user_products, \@item);
        }
    }
    $vars->{'user_products'} = \@user_products;
}

sub update_team_bugs {
    my ($vars, $list_is_backlog) = @_;

    my $cgi     = Bugzilla->cgi;
    my $team_id = $cgi->param('obj_id');
    my $data    = $cgi->param('data');

    my $user  = Bugzilla->user();
    my $team  = Bugzilla::Extension::Scrums::Team->new($team_id);
    my $error = "";

    if ($list_is_backlog) {
        if (($team->owner() != $user->id()) && (not Bugzilla->user->in_group('scrums_editteams'))) {
            # User error can not be used, because this is ajax-call
            $error = 'You must be the owner of the team to edit the backlog.';
        }
    }
    else {
        if ((not $team->is_user_team_member($user)) && (not Bugzilla->user->in_group('scrums_editteams'))) {
            # User error can not be used, because this is ajax-call
            $error = 'You must be a member of the team to edit the sprint.';
        }
    }

    if ($error ne "") {
        $vars->{'errors'} = $error;
    }
    else {
        update_bug_order_from_json($team_id, $data, $vars);
    }
}

sub move_pending_items {
    my ($data, $list_is_backlog, $team_id, $vars) = @_;

    my $user  = Bugzilla->user();
    my $team  = Bugzilla::Extension::Scrums::Team->new($team_id);
    my $error = "";

    if ($list_is_backlog) {
        if (($team->owner() != $user->id()) && (not Bugzilla->user->in_group('scrums_editteams'))) {
            # User error can not be used, because this is ajax-call
            $error = 'You must be the owner of the team to edit the backlog.';
        }
    }
    else {
        if ((not $team->is_user_team_member($user)) && (not Bugzilla->user->in_group('scrums_editteams'))) {
            # User error can not be used, because this is ajax-call
            $error = 'You must be a member of the team to edit the sprint.';
        }
    }
    insert_item_list_into_sprint($data, $vars);
}

sub _update_team {
    my ($team, $name, $owner, $scrum_master, $is_using_backlog) = @_;

    my $error = "";
    if ($name =~ /^([-\ \w]+)$/) {
        $name = $1;    # $data now untainted
    }
    else {
        $error = " Illegal name";
        $name  = "";
    }

    if ($owner =~ /^([0-9]+)$/) {
        $owner = $1;    # $data now untainted
    }
    else {
        $error .= " Illegal owner";
        $owner = "";
    }

    if ($scrum_master =~ /^([0-9]+)$/) {
        $scrum_master = $1;    # $data now untainted
    }
    else {
        $scrum_master = "";
    }

    if ($is_using_backlog =~ /^([0-9])$/) {
        $is_using_backlog = $1;    # $data now untainted
    }

    if ($error eq "") {
        $team->set_name($name);
        $team->set_owner($owner);
        $team->set_scrum_master($scrum_master);
        $team->set_is_using_backlog($is_using_backlog);
        $team->update();
    }

    return $error;
}

1;

__END__

=head1 NAME

Scrums::Teams - Scrums function library for team related features.

Uses Scrums::Team

=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Teams;

    Bugzilla::Extension::Scrums::Teams::show_all_teams($vars);
    Bugzilla::Extension::Scrums::Teams::show_create_team($vars);
    Bugzilla::Extension::Scrums::Teams::add_into_team($vars);
    Bugzilla::Extension::Scrums::Teams::search_person($vars);
    Bugzilla::Extension::Scrums::Teams::edit_team($vars);
    Bugzilla::Extension::Scrums::Teams::show_team_bugs($vars);
    Bugzilla::Extension::Scrums::Teams::update_team_bugs($vars, $list_is_backlog);

=head1 DESCRIPTION

Teams.pm is a library, that contains all teams related functionalities. It is interface to server and its functions must be called with CGI-variables in hash-map.

=head1 METHODS

=over

=item C<show_all_teams($vars)>

 Description: Returns name of the team.

 cgi:         The following keys in hashref are optional:
              deleteteam         - Id (integer) of team, that is deleted from database
              sort               - Code (integer) of sorting order for array of teams

 Returns:     The vars-hashref is added the following keys:
              sort               - Sorting order is returned back to client
              teamlist           - Reference to an array of Bugzilla::Extension::Scrums::Team objects.


=item C<show_create_team($vars)>

 Description: Returns name of the team.

 cgi:         The hashref must have the following keys:
              teamid             - Id (integer) of Bugzilla::Extension::Scrums::Team object
              The following keys in hashref are optional:
              removedcomponent   - Removed component, id (integer) of A Bugzilla::Component object
              component          - Added component, id (integer) of A Bugzilla::Component object
              editteam           - Indicates, that team information is updated. This variable is either defined or not.
              name               - Updated name of the team
              userid             - Updated owner of the team, Id (integer) of a Bugzilla::User object
              scrummasterid      - Updated scrum master of the team, Id (integer) of a Bugzilla::User object
              usesbacklog        - Whether team uses backlog or not (when team information is updated)


 Returns:     The vars-hashref is added the following keys:
              team               - Bugzilla::Extension::Scrums::Team object
              active_sprint      - Bugzilla::Extension::Scrums::Sprint object
              active_sprint_id   - Id (integer) of Bugzilla::Extension::Scrums::Sprint object
              active_sprint_name - Name of active sprint
	      teamisnew          - Indicates, that new team was created. This variable is either defined or not.

=item C<add_into_team($vars)>

 Description: Puts given user information into template variables.

 Returns:     The vars-hashref is added the following keys, that are all read from cgi-hashref:
              userid             - Id (integer) of a Bugzilla::User object
              teamid             - Id (integer) of Bugzilla::Extension::Scrums::Team object
              userrealname       - Real name from Bugzilla::User object
              userlogin          - Login name from Bugzilla::User object
              teamname           - Name of team


=item C<search_person($vars)>

 Description: Creates SQL-query based on CGI-parameters. Executes query and forwards results into template.

 cgi:         The hashref must have the following keys:
              matchvalue         - Indicates, which profile field is used as search criteria
              matchstr           - String value to be searched in SQL query
              matchtype          - Possible values are 'regexp', 'notregexp', 'exact' or other

 Returns:     The vars-hashref is added the following keys:
              query              - Complete query string
              users              - Reference to a table of data, that represents list of users.
              The vars-hashref is added the following keys, that are all read from cgi-hashref:
              formname           - Return address for template form
              formfieldprefix    - Return address for template form
              submit             - Action for template form

 Returns:     String.

=item C<edit_team($vars)>

 Description: Puts information of given team into template variables.

 cgi:         The hashref must have the following keys: 
              teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object

 Returns:     The vars-hashref is added the following keys:
              team                 - Bugzilla::Extension::Scrums::Team object
              The vars-hashref is added the following keys, that are all read from cgi-hashref:
              editteam             - Action for template form
              teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object
              realname             - Real name from Bugzilla::User object
              scrummasterrealname  - Real name from Bugzilla::User object
              scrummasterloginname - Login name from Bugzilla::User object

=item C<show_team_bugs($vars)>

 Description: Fetches all information of a team into template variables.

 cgi:         The hashref must have the following keys: 
              teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object

 Returns:     The vars-hashref is added the following keys:
              team                 - Bugzilla::Extension::Scrums::Team object
              unprioritised_bugs   - Reference to a table of data, that represents list of bugs.
              active_sprint        - Bugzilla::Extension::Scrums::Sprint object
              capacity             - Capacity summary from active sprint
              history              - Sprint history information
              active_sprint_id     - Id (integer) of Bugzilla::Extension::Scrums::Sprint object
              backlog_id           - Id (integer) of Bugzilla::Extension::Scrums::Sprint object
              bug_status_open      - List of all bug states, that are open
              components           - List of all components of team
              products             - List of products, that team's components belong
              classifications      - List of classifications, that team's components belong



=item C<update_team_bugs($vars, $list_is_backlog)>

 Description: Updates bug lists according to JSON text, that was received from client.

 Params:      list_is_backlog     - Backlog requires different user rights

 cgi:         The hashref must have the following keys: 
              obj_id              - Team id, id (integer) of Bugzilla::Extension::Scrums::Team object
              data                - JSON text, that contains bug lists

 Returns:     The vars-hashref is added the following keys:
              errors              - Possible errors (string) to be returned as Ajax return value
              warnings            - Possible warnings (string) to be returned as Ajax return value

=back

=cut

