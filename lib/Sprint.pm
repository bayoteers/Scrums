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
# The Original Code is the Ultimate Scrum Bugzilla Extension.
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
#use Bugzilla::Error;

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

use constant VALIDATORS => {};

###############################
####     Constructors     #####
###############################
# This is necessary method only when transaction handling is needed for multiple tables
#sub remove_from_db {
#    my $self = shift;
#    my $dbh = Bugzilla->dbh;
#    $dbh->bz_start_transaction();
#    $self->SUPER::remove_from_db();
#
#    $dbh->bz_commit_transaction();
#}

###############################
####      Validators       ####
###############################
#

###############################
####       Methods         ####
###############################

sub get_bugs {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($sprint_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        p.realname,
        b.bug_status,
        left(b.short_desc, 40),
        b.remaining_time,
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

sub nominal_schedule {
    my $self     = shift;
    my $str_date = $self->{'nominal_schedule'};
    return $self->replace_dash_with_dot($str_date);
}

sub start_date {
    my $self     = shift;
    my $str_date = $self->{'start_date'};
    return $self->replace_dash_with_dot($str_date);
}

sub end_date {
    my $self     = shift;
    my $str_date = $self->{'end_date'};
    return $self->replace_dash_with_dot($str_date);
}

sub replace_dash_with_dot {
    my $self            = shift;
    my $str_with_dashes = shift;
    my $str_with_dots   = $str_with_dashes;
    if ($str_with_dashes ne "") {
        if ($str_with_dashes =~ /^(\d{4})-(\d{1,2})-(\d{1,2})/) {
            $str_with_dots = "$1.$2.$3";
        }
    }
    return $str_with_dots;
}

1;

__END__

