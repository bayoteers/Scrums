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

use strict;

package Bugzilla::Extension::Scrums::Sprint;

#use Bugzilla::Constants;
#use Bugzilla::Util;
use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
#

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_sprints';
use constant LIST_ORDER => 'nominal_schedule';

use constant DB_COLUMNS => qw(
  id
  team_id
  name
  nominal_schedule
  status
  is_active
  description
  start_date
  end_date
  estimated_capacity
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  team_id
  name
  nominal_schedule
  status
  is_active
  );

use constant UPDATE_COLUMNS => qw(
  name
  nominal_schedule
  status
  is_active
  description
  start_date
  end_date
  estimated_capacity
  );

use constant VALIDATORS => { start_date => \&_check_start_date, end_date => \&_check_end_date };

###############################
####     Constructors     #####
###############################

###############################
####      Validators       ####
###############################

sub _check_start_date {
    my ($self, $start_date) = @_;

    $self->_check_date($start_date);
    return $start_date;
}

sub _check_end_date {
    my ($self, $end_date) = @_;

    $self->_check_date($end_date);
    return $end_date;
}

sub _check_date {
    my ($self, $tested_date) = @_;

    my $team_id = team_id();
    my ($sprint_id, $name, $start_date, $end_date);

    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare(
        "select 
                        id, 
                        name, 
                        start_date, 
                        end_date        
                from 
                        scrums_sprints 
                where 
                        item_type = 1 and 
                        (start_date is null or end_date is null) and 
                        team_id = ?"
                           );

    if ($tested_date == undef) {
        return;
    }

    $sth->execute($team_id);
    if (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
        if ($self->id && $self->id != $sprint_id) {
            if (!$start_date) {
                $start_date = "null";
            }
            if (!$end_date) {
                $end_date = "null";
            }
            ThrowUserError('scrums_overlapping_sprint', { 'name' => $name, 'start' => $start_date, 'end' => $end_date });
        }
    }

    $sth = $dbh->prepare(
        "select 
                        id, 
                        name, 
                        start_date, 
                        end_date 
                from 
                        scrums_sprints 
                where 
                        item_type = 1 and 
                        (start_date < ? or start_date is null) and 
                        (end_date > ? or end_date is null) and 
                        team_id = ?"
                        );
    $sth->execute($tested_date, $tested_date, $team_id);
    if (($sprint_id, $name, $start_date, $end_date) = $sth->fetchrow_array) {
        if ($self->id && $self->id != $sprint_id) {
            if (!$start_date) {
                $start_date = "null";
            }
            if (!$end_date) {
                $end_date = "null";
            }
            ThrowUserError('scrums_overlapping_sprint', { 'name' => $name, 'start' => $start_date, 'end' => $end_date });
        }
    }
}

###############################
####       Methods         ####
###############################

sub get_bugs {
    my $self = shift;
    if (!$self->{'my_bugs'}) {
        $self->set('my_bugs', $self->_fetch_bugs());
    }
    return $self->{'my_bugs'};
}

sub get_work_done {
    my $self = shift;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare(
        'select
            sum(work_time) as w
        from 
            longdescs ld
        inner join
            scrums_sprint_bug_map sbm on
            sbm.bug_id = ld.bug_id
        where
            sprint_id = ? and 
            work_time > 0'
                           );
    $sth->execute($self->id);
    my ($work_done) = $sth->fetchrow_array();
    return $work_done;
}

sub get_capacity_summary {
    my $self = shift;

    my %capacity;
    my $capacity = \%capacity;
    my $estimate = $self->estimated_capacity();

    my $work_done = $self->get_work_done();

    my $remaining_work = $self->calculate_remaining();

    $capacity{sprint_capacity} = $estimate;
    $capacity{work_done}       = $work_done;
    $capacity{remaining_work}  = $remaining_work;
    $capacity{free_capacity}   = $estimate - $work_done - $remaining_work;
    return $capacity;
}

sub calculate_remaining {
    my $self = shift;

    my $cum_rem     = 0;
    my $sprint_bugs = $self->get_bugs();
    for my $bug (@$sprint_bugs) {
        $cum_rem = $cum_rem + @$bug[1];
    }
    return $cum_rem;
}

sub _fetch_bugs {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($sprint_bugs) = $dbh->selectall_arrayref(
        'select
	    b.bug_id,
        b.remaining_time,
        b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc,
        bo.team,
        b.creation_ts
    from
	scrums_sprint_bug_map sbm
	inner join bugs b on sbm.bug_id = b.bug_id
        inner join profiles p on p.userid = b.assigned_to
	left join scrums_bug_order bo on sbm.bug_id = bo.bug_id
    where
	sbm.sprint_id = ?
    order by
	bo.team', undef, $self->id
    );
    return $sprint_bugs;
}

sub set_name               { $_[0]->set('name',               $_[1]); }
sub set_nominal_schedule   { $_[0]->set('nominal_schedule',   $_[1]); }
sub set_status             { $_[0]->set('status',             $_[1]); }
sub set_is_active          { $_[0]->set('is_active',          $_[1]); }
sub set_description        { $_[0]->set('description',        $_[1]); }
sub set_start_date         { $_[0]->set('start_date',         $_[1]); }
sub set_end_date           { $_[0]->set('end_date',           $_[1]); }
sub set_estimated_capacity { $_[0]->set('estimated_capacity', $_[1]); }

###############################
### Testing utility methods ###
###############################

sub add_bug_into_sprint {
    my $self = shift;
    my ($added_bug_id, $preceding_bug_id) = @_;

    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my $sth1 = $dbh->prepare(
        'select 
        team 
    from
        scrums_bug_order
    where
        bug_id = ?'
                            );
    $sth1->execute($preceding_bug_id);
    my ($preceding_team) = $sth1->fetchrow_array;

    $dbh->do('INSERT INTO scrums_sprint_bug_map (bug_id, sprint_id) values (?, ?)', undef, $added_bug_id, $self->{'id'});

    $dbh->do(
        'update
        scrums_bug_order bo
    set
        team = team + 1
    where exists
    (select null from
        scrums_sprint_bug_map sbm
    inner join
        scrums_sprints s
    on
        s.id = sbm.sprint_id and
        s.team_id = ? and
        s.is_active = 1
    where
        sbm.bug_id = bo.bug_id and
        team > ?)', undef, $self->{'team_id'}, $preceding_team
    );

    $dbh->do('INSERT INTO scrums_bug_order (bug_id, team) values (?, ?)', undef, $added_bug_id, $preceding_team + 1);

    $dbh->bz_commit_transaction();
}

###############################
####      Accessors        ####
###############################

sub name               { return $_[0]->{'name'}; }
sub status             { return $_[0]->{'status'}; }
sub is_active          { return $_[0]->{'is_active'}; }
sub description        { return $_[0]->{'description'}; }
sub team_id            { return $_[0]->{'team_id'}; }
sub estimated_capacity { return $_[0]->{'estimated_capacity'}; }

sub nominal_schedule {
    my $self = shift;
    return $self->{'nominal_schedule'};
}

sub start_date {
    my $self = shift;
    return $self->{'start_date'};
}

sub end_date {
    my $self = shift;
    return $self->{'end_date'};
}

sub is_current {
    my $self = shift;
    use Time::Local;
    my $now = time;
    my ($yyyy, $mm, $dd) = ($self->start_date() =~ /(\d+)-(\d+)-(\d+)/);
    my $sdate = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);
    my ($yyyy, $mm, $dd) = ($self->end_date() =~ /(\d+)-(\d+)-(\d+)/);
    my $edate = timelocal(0, 0, 0, $dd, $mm-1, $yyyy);

    return ($now >= $sdate and $now <= $edate)
}

1;

__END__

