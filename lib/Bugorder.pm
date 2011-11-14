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

use base qw(Bugzilla::Object);

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

=head1 NAME

Bugzilla::Extension::Scrums::Bugorder - Scrums bugorder class.

=head1 SYNOPSIS

    use Bugzilla::Extension::Scrums::Bugorder;
    my $order = Bugzilla::Extension::Scrums::Bugorder->new($bug_id);

    my $team_order      = $order->team_order();
    my $release_order   = $order->release_order();
    my $program_order   = $order->program_order();

    my $order = Bugzilla::Extension::Scrums::Bugorder->create({ bug_id => $bug_id });

    $order->set_team_order($team_order);
    $order->set_release_order($release_order);
    $order->set_program_order($program_order);

    $order->update();

    $order->remove_from_db;

=head1 DESCRIPTION

Bugorder object represent order in priority of a bug. A bug can be prioritised in several different ways.
Bugorder represents all these priority values. Order is visualised and modified as ordered lists of bugs.

=head1 METHODS

=over

=item C<new($bug_id)>

 Description: The constructor is used to load an existing bugorder
              by passing a bug ID.

 Params:      $bug -   Id of the bug (integer).

 Returns:     A Bugzilla::Extension::Scrums::Bugorder object.

=item C<team_order()>

 Description: Returns order of a bug in team priority.

 Params:      none.

 Returns:     Team order (integer).

=item C<release_order()>

 Description: Returns order of a bug in release priority.

 Params:      none.

 Returns:     Release order (integer).

=item C<program_order()>

 Description: Returns order of a bug in program priority.

 Params:      none.

 Returns:     Program order (integer).

=item C<set_team_order($team_order)>

 Description: Sets order of a bug in team priority.

 Params:      Team order (integer).

 Returns:     Nothing.

=item C<set_release_order($release_order)>

 Description: Sets order of a bug in release priority.

 Params:      Release order (integer).

 Returns:     Nothing.

=item C<set_program_order($program_order)>

 Description: Sets order of a bug in program priority.

 Params:      Program order.

 Returns:     Nothing.

=back

=head1 CLASS METHODS

=over

=item C<create(\%params)>

 Description: Create a new bugorder.

 Params:      The hashref must have the following keys:
              bug_id          - Id of the Bugzilla::Bug object (Integer).

 Returns:     A Bugzilla::Extension::Scrums::Bugorder object.

=back

=cut

