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

    my $team_id = $self->team_id();
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
    my $dbh  = Bugzilla->dbh;
    my ($sprint_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.remaining_time,
        b.bug_status,
        p.realname,
        left(b.short_desc, 40),
        b.short_desc,
	bo.team
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

sub set_name             { $_[0]->set('name',             $_[1]); }
sub set_nominal_schedule { $_[0]->set('nominal_schedule', $_[1]); }
sub set_status           { $_[0]->set('status',           $_[1]); }
sub set_is_active        { $_[0]->set('is_active',        $_[1]); }
sub set_description      { $_[0]->set('description',      $_[1]); }
sub set_start_date       { $_[0]->set('start_date',       $_[1]); }
sub set_end_date         { $_[0]->set('end_date',         $_[1]); }

###############################
####      Accessors        ####
###############################

sub name        { return $_[0]->{'name'}; }
sub status      { return $_[0]->{'status'}; }
sub is_active   { return $_[0]->{'is_active'}; }
sub description { return $_[0]->{'description'}; }
sub team_id     { return $_[0]->{'team_id'}; }

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

1;

__END__

