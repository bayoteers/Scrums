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

package Bugzilla::Extension::Scrums::Sprinthandle;

use Bugzilla::Extension::Scrums::Team;
use Bugzilla::Extension::Scrums::Sprint;
use Bugzilla::Extension::Scrums::Sprintslib;
use Bugzilla::Extension::Scrums::Teamorderlib;

use Bugzilla::Util qw(trick_taint);
use Bugzilla::Util;
use Bugzilla::Error;

use strict;
use base qw(Exporter);
our @EXPORT = qw(
  new_sprint
  update_sprint
  delete_sprint
  show_sprint
  show_archived_sprints
  );

sub show_sprint {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    my @sprints;

    my $teamid;
    if ($cgi->param('teamid') =~ /(\d+)/) {
        $teamid = $1;
    }

    my $sprintid;
    if ($cgi->param('sprintid') =~ /(\d+)/) {
        $sprintid = $1;
    }

    my $sprints = undef;
    if ($sprintid =~ /(\d+)/) {
        $sprintid = $1;
        $sprints = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $teamid, id => $sprintid, item_type => 1 });
    }

    $vars->{'json_text'} = '';
    if ($sprints) {
        use JSON;
        use Data::Dumper qw(Dumper);
        for my $sprint (@{$sprints}) {
            $vars->{'sprint'}            = $sprint;
            $vars->{'prediction'}        = $sprint->get_predictive_estimate()->{'prediction'};
            $vars->{'history'}           = $sprint->get_predictive_estimate()->{'history'};
            $vars->{'estimatedcapacity'} = $sprint->estimated_capacity();
            $vars->{'personcapacity'}    = $sprint->get_person_capacity();
            $vars->{'json_text'} = to_json(
                {
                   name        => $sprint->name(),
                   id          => $sprint->id(),
                   bugs        => $sprint->get_bugs(),
                   description => $sprint->description(),
                   _status     => $sprint->status(),
                   end_date    => $sprint->end_date(),
                   start_date  => $sprint->start_date()
                }    # json_text is not used!
            );
        }
    }
}

sub show_archived_sprints {
    my ($vars) = @_;

    my $team_id = Bugzilla->cgi->param('teamid');
    $vars->{'team'} = Bugzilla::Extension::Scrums::Team->new($team_id);
    my $archived_sprints = Bugzilla::Extension::Scrums::Sprint->match({ team_id => $team_id, item_type => 1 });
    pop(@{$archived_sprints});
    my @team_sprints_array;
    for my $sprint (@{$archived_sprints}) {
        my $spr_bugs = $sprint->get_bugs();
        my %team_sprint;
        $team_sprint{'sprint'} = $sprint;
        $team_sprint{'bugs'}   = $spr_bugs;
        unshift @team_sprints_array, \%team_sprint;
    }
    $vars->{'team_sprints_array'} = \@team_sprints_array;
}

sub new_sprint {
    my ($vars) = @_;

    my $cgi          = Bugzilla->cgi;
    my $error        = "";
    my $teamid       = $cgi->param('teamid');
    my $name         = $cgi->param('sprintname');
    my $description  = $cgi->param('description');
    my $start_date   = $cgi->param('start_date');
    my $end_date     = $cgi->param('end_date');
    my $est_capacity = $cgi->param('estimatedcapacity');
    my $take_bugs    = $cgi->param('takebugs');

    ($error, $teamid, $name, $description, $start_date, $end_date, $est_capacity) =
      _sanitise_sprint_data($teamid, $name, $description, $start_date, $end_date, $est_capacity);

    my $sprint;
    if ($teamid and $name) {

        my $err = Bugzilla::Extension::Scrums::Sprint->validate_span(undef, $teamid, $start_date, $end_date);

        if ($err) {
            $vars->{errors} = $err;
            return;
        }
        else {

            my $team           = Bugzilla::Extension::Scrums::Team->new($teamid);
            my $current_sprint = $team->get_team_current_sprint();

            # It looks like this transaction would not work at all because method Bugzilla::Object::Unpdate
            # does not allow database handle to be given as parameter. That would mean, that
            # new transaction will be started in update method although another transaction already started.
            # This might not however have effect. According to Bugzilla documentation transaction
            # can be started inside another transaction, but commit will not be done unless
            # commit method is called as many times as transaction has been started. If this holds,
            # it would have exactly wanted result.
            $sprint = Bugzilla::Extension::Scrums::Sprint->create(
                                                                  {
                                                                    team_id            => $teamid,
                                                                    status             => "NEW",
                                                                    name               => $name,
                                                                    description        => $description,
                                                                    item_type          => 1,
                                                                    start_date         => $start_date,
                                                                    end_date           => $end_date,
                                                                    estimated_capacity => $est_capacity
                                                                  }
                                                                 );

            my $bug_array = [];
            if ($take_bugs && $current_sprint) {
                my $bug_id_array = $current_sprint->get_remaining_item_array();
                $bug_array = Bugzilla::Bug->new_from_list($bug_id_array);
            }

            my $dbh = Bugzilla->dbh;
            $dbh->bz_start_transaction();
            $sprint->initialise_with_old_bugs($bug_array);
            $dbh->bz_commit_transaction();
        }
    }
    else {
        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => $error });
    }
    return $sprint->id();
}

sub update_sprint {
    my ($vars) = @_;

    my $cgi          = Bugzilla->cgi;
    my $error        = "";
    my $teamid       = $cgi->param('teamid');
    my $name         = $cgi->param('sprintname');
    my $description  = $cgi->param('description');
    my $start_date   = $cgi->param('start_date');
    my $end_date     = $cgi->param('end_date');
    my $est_capacity = $cgi->param('estimatedcapacity');

    my $sprint_id = $cgi->param('sprintid');
    if ($sprint_id && $sprint_id =~ /^([0-9]+)$/) {
        $sprint_id = $1;    # $data now untainted
    }
    else {
        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => " Invalid Sprint ID" });
    }

    ($error, $teamid, $name, $description, $start_date, $end_date, $est_capacity) =
      _sanitise_sprint_data($teamid, $name, $description, $start_date, $end_date, $est_capacity);

    if ($sprint_id and $name) {
        my $sprint = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);

        my $err = Bugzilla::Extension::Scrums::Sprint->validate_span($sprint_id, $teamid, $start_date, $end_date);
        if ($err) {
            $vars->{errors} = $err;
        }
        else {
            $sprint->set_name($name);
            $sprint->set_start_date($start_date);
            $sprint->set_end_date($end_date);
            $sprint->set_description($description);
            $sprint->set_estimated_capacity($est_capacity);
            $sprint->update();
        }
    }
    else {
        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => $error });
    }
}

sub delete_sprint {
    my $cgi       = Bugzilla->cgi;
    my $sprint_id = $cgi->param('sprintid');
    if ($sprint_id =~ /^([0-9]+)$/) {
        $sprint_id = $1;    # $data now untainted
    }
    else {
        ThrowUserError('scrums_team_can_not_be_updated', { invalid_data => " Invalid Sprint ID" });
    }

    my $sprint      = Bugzilla::Extension::Scrums::Sprint->new($sprint_id);
    my $sprint_bugs = $sprint->get_bugs();
    if (scalar @{$sprint_bugs} > 0) {
        ThrowUserError('sprint_has_bugs');
    }
    $sprint->remove_from_db();
}

sub _sanitise_sprint_data {
    my ($teamid, $name, $description, $start_date, $end_date, $est_capacity) = @_;
    my $error = "";

    if ($teamid =~ /^([0-9]+)$/) {
        $teamid = $1;    # $data now untainted
    }
    else {
        $error .= " Illegal team id";
        $teamid = "";
    }

    if ($name =~ /^(\S.*)/) {
        $name = $1;      # $data now untainted
    }
    else {
        $error .= " Illegal name";
        $name = "";
    }

    if ($description =~ /(.*)/) {
        $description = $1;    # $data now untainted
    }
    else {
        $error .= " Illegal description";
        $description = "";
    }

    if ($start_date =~ /^(\d{4}-\d{1,2}-\d{1,2})/) {
        $start_date = $1;     # $data now untainted
    }
    else {
        $error .= " Illegal start date";
        $start_date = undef;
    }

    if ($end_date =~ /^(\d{4}-\d{1,2}-\d{1,2})/) {
        $end_date = $1;       # $data now untainted
    }
    else {
        $error .= " Illegal end date";
        $end_date = undef;
    }

    if ($est_capacity =~ /(.*)/) {
        $est_capacity = $1;    # $data now untainted
    }

    return ($error, $teamid, $name, $description, $start_date, $end_date, $est_capacity);
}

1;

__END__

=head1 NAME

Scrums::Sprinthandle - Scrums function library for handling sprints.

Uses Scrums::Sprint

=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Sprinthandle;

    Bugzilla::Extension::Scrums::Sprinthandle::show_sprint($vars);
    Bugzilla::Extension::Scrums::Sprinthandle::show_archived_sprints($vars);
    Bugzilla::Extension::Scrums::Sprinthandle::new_sprint($vars);
    Bugzilla::Extension::Scrums::Sprinthandle::update_sprint($vars);
    Bugzilla::Extension::Scrums::Sprinthandle::delete_sprint($vars);

=head1 DESCRIPTION

Sprinthandle.pm is a library, that contains all functionalities related manipulating sprint object. It is interface to server and its functions must be called with CGI-variables in hash-map.

=head1 METHODS

=over

=item C<show_sprint($vars)>

 Description: Fetches data of given sprint to be formatted as Json-sprint.

 vars:        The hashref must have the following keys:
              sprint_id       - id of a Bugzilla::Extension::Scrums::Sprint object of team owner.

 Returns:     The vars-hashref is added the following keys:
	      sprint		 - Sprint object including its items
              prediction         - Predictive estimate, that is based on history data
              history		 - History data of previous sprints
              estimatedcapacity  - Estimated capacity of the sprint in hours
              personcapacity     - Estimated effort of the sprint as allocated persons


=item C<show_archived_sprints($vars)>

 Description: Puts information of archived sprints into template variables.

 cgi:         The hashref must have the following keys: 
              teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object

 Returns:     The vars-hashref is added the following keys:
              team                 - Bugzilla::Extension::Scrums::Team object
              team_sprints_array   - Array of Bugzilla::Extension::Scrums::Sprint objects


=item C<new_sprint($vars)>

 Description: Creates new Sprint object and moves open bugs from old sprint to new, if requested.

 Params:      teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object
              sprintname           - Name of sprint
              description          - Description of sprint
              start_date           - Startind day of sprint
              end_date             - Ending day of sprint
              estimatedcapacity    - Estimated capacity of the sprint in hours
              takebugs             - Indicates, that old open bugs are to be moved into created sprint

 Returns:     Id (integer) of Bugzilla::Extension::Scrums::Sprint object.


=item C<update_sprint($vars)>

 Description: 

 Params:      sprintid             - Id (integer) of Bugzilla::Extension::Scrums::Sprint object
              teamid               - Id (integer) of Bugzilla::Extension::Scrums::Team object
              sprintname           - Name of sprint
              description          - Description of sprint
              start_date           - Startind day of sprint
              end_date             - Ending day of sprint
              estimatedcapacity    - Estimated capacity of the sprint in hours

 Returns:     Nothing.


=item C<delete_sprint($vars)>

 Description: Deletes sprint from database

 Params:      sprintid             - Id (integer) of Bugzilla::Extension::Scrums::Sprint object

 Returns:     Nothing.

=back

=cut

