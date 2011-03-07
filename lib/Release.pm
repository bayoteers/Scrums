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
# The Initial Developer of the Original Code is YOUR NAME
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Visa Korhonen <visa.korhonen@symbio.com>

use strict;

package Bugzilla::Extension::Scrums::Release;

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
# TODO Move to Bugzilla/Constants.pm
# The longest release name allowed.
use constant MAX_RELEASE_SIZE => 64;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_releases';
use constant LIST_ORDER => 'name';

use constant DB_COLUMNS => qw(
  id
  name
  target_milestone_begin
  target_milestone_end
  capacity_algorithm
  original_capacity
  remaining_capacity
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  name
  );

use constant UPDATE_COLUMNS => qw(
  name
  target_milestone_begin
  target_milestone_end
  capacity_algorithm
  original_capacity
  remaining_capacity
  );

use constant VALIDATORS => { name => \&_check_name, };

###############################
####     Constructors     #####
###############################
# This is necessary method only because transaction handling is needed for multiple tables
sub remove_from_db {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;

    $dbh->bz_start_transaction();

    my $release_id = $self->id;
    Bugzilla->dbh->do('delete from scrums_flagtype_release_map where release_id = ?', undef, $release_id);

    $self->SUPER::remove_from_db();

    $dbh->bz_commit_transaction();
}

###############################
####      Validators       ####
###############################

sub _check_name {
    my ($invocant, $name) = @_;

    $name = trim($name);
    $name || ThrowUserError('release_not_specified');

    if (length($name) > MAX_RELEASE_SIZE) {
        # TODO define user error
        ThrowUserError('release_name_too_long', { 'name' => $name });
    }

    my $release = new Bugzilla::Extension::Scrums::Release({ name => $name });
    if ($release && (!ref $invocant || $release->id != $invocant->id)) {
        # TODO define user error
        ThrowUserError("release_already_exists", { name => $release->name });
    }
    return $name;
}

###############################
####       Methods         ####
###############################

sub set_name                   { $_[0]->set('name',                   $_[1]); }
sub set_target_milestone_begin { $_[0]->set('target_milestone_begin', $_[1]); }
sub set_target_milestone_end   { $_[0]->set('target_milestone_end',   $_[1]); }
sub set_capacity_algorithm     { $_[0]->set('capacity_algorithm',     $_[1]); }
sub set_original_capacity      { $_[0]->set('capacity_algorithm',     $_[1]); }
sub set_remaining_capacity     { $_[0]->set('capacity_algorithm',     $_[1]); }

sub set_flag_type {
    my ($self, $type_id) = @_;
    my $release_id = $self->id;
    Bugzilla->dbh->do('INSERT INTO scrums_flagtype_release_map (flagtype_id, release_id) VALUES (?, ?)', undef, $type_id, $release_id);
}

sub remove_flag_type {
    my ($self, $type_id) = @_;
    my $release_id = $self->id;
    Bugzilla->dbh->do('DELETE FROM scrums_flagtype_release_map WHERE flagtype_id = ? AND release_id = ?', undef, $type_id, $release_id);
}

###############################
####      Accessors        ####
###############################

sub name                   { return $_[0]->{'name'}; }
sub target_milestone_begin { return $_[0]->{'target_milestone_begin'}; }
sub target_milestone_end   { return $_[0]->{'target_milestone_end'}; }
sub capacity_algorithm     { return $_[0]->{'capacity_algorithm'}; }
sub original_capacity      { return $_[0]->{'original_capacity'}; }
sub remaining_capacity     { return $_[0]->{'remaining_capacity'}; }

sub flag_types {
    my $self = shift;
    return $self->{'flag_types'} if exists $self->{'flag_types'};
    return [] if $self->{'error'};

    my $dbh = Bugzilla->dbh;
    my $flag_type_ids = $dbh->selectcol_arrayref('SELECT flagtype_id FROM scrums_flagtype_release_map WHERE release_id = ?', undef, $self->id);
    $self->{'flag_types'} = Bugzilla::FlagType->new_from_list($flag_type_ids);
    return $self->{'flag_types'};
}

sub scheduled_bugs {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($scheduled_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.bug_status,
        b.bug_severity,
        left(b.short_desc, 40),
	bo.rlease
    from
	scrums_flagtype_release_map rfm
	inner join flags f on rfm.flagtype_id = f.type_id
	inner join bugs b on f.bug_id = b.bug_id
	inner join scrums_bug_order bo on f.bug_id = bo.bug_id
    where
	f.status = "+" and
        bo.rlease > 0 and
	rfm.release_id = ?
    order by
	rlease', undef, $self->id
    );
    return $scheduled_bugs;
}

sub unprioritised_bugs {
    my $self = shift;
    my $dbh  = Bugzilla->dbh;
    my ($unprioritised_bugs) = $dbh->selectall_arrayref(
        'select
	b.bug_id,
        b.bug_status,
        b.bug_severity,
        left(b.short_desc, 40)
    from
	scrums_flagtype_release_map rfm
	inner join flags f on rfm.flagtype_id = f.type_id
	inner join bugs b on f.bug_id = b.bug_id
    where
	not exists (select null from scrums_bug_order bo where f.bug_id = bo.bug_id and bo.rlease > 0) and
	f.status = "+" and
	rfm.release_id = ?', undef, $self->id
    );
    return $unprioritised_bugs;
}

1;

__END__

