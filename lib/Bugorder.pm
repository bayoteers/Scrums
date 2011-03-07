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

package Bugzilla::Extension::Scrums::Bugorder;

#use Bugzilla::Constants;
#use Bugzilla::Util;
#use Bugzilla::Error;

use base qw(Bugzilla::Object);

##### Constants
#

###############################
####    Initialization     ####
###############################

use constant DB_TABLE   => 'scrums_bug_order';
use constant ID_FIELD   => 'bug_id';
use constant LIST_ORDER => 'bug_id';

use constant DB_COLUMNS => qw(
  bug_id
  team
  rlease
  program
  );

use constant REQUIRED_CREATE_FIELDS => qw(
  bug_id
  );

use constant UPDATE_COLUMNS => qw(
  team
  rlease
  program
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

sub set_team_order    { $_[0]->set('team',    $_[1]); }
sub set_release_order { $_[0]->set('rlease',  $_[1]); }
sub set_program_order { $_[0]->set('program', $_[1]); }

###############################
####      Accessors        ####
###############################

sub team_order    { return $_[0]->{'team'}; }
sub release_order { return $_[0]->{'rlease'}; }
sub program_order { return $_[0]->{'program'}; }

1;

__END__

