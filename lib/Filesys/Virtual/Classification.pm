package Filesys::Virtual::Classification;

use strict;
use warnings;

use Filesys::Virtual::Attachments ();
our @ISA = ('Filesys::Virtual::Attachments');

#use Data::Dump qw(dump);

use constant NOCAT => '00.uncategorized';
use constant NOTAG => '00.untagged';

sub new {
  my $class = shift;
  my $args = shift;

  my $this = bless($class->SUPER::new($args), $class);

  $Filesys::Virtual::Foswiki::FILES_EXT = '';
  @Filesys::Virtual::Foswiki::views = ();

  $this->{hideEmpty} = $Foswiki::cfg{Plugins}{FilesysVirtualPlugin}{HideEmpty}
    || 0;

  return $this;
}

sub _parseResource {
  my ($this, $resource) = @_;

  if (defined $this->{location} && $resource =~ s/^$this->{location}//) {

    # Absolute path; must be, cos it has a location
  } elsif ($resource !~ /^\//) {

    # relative path
    $resource = $this->{path} . '/' . $resource;
  }
  $resource =~ s/\/\/+/\//g;    # normalise // -> /
  $resource =~ s/^\/+//;        # remove leading /

  # Resolve the path into it's components
  my @path;
  foreach (split(/\//, $resource)) {
    if ($_ eq '..') {
      if ($#path) {
        pop(@path);
      }
    } elsif ($_ eq '.') {
      next;
    } elsif ($_ eq '~') {
      @path = ($Foswiki::cfg{UsersWebName});
    } else {
      push(@path, $_);
    }
  }

  # strip off hidden attribute from filename
  @path = map {$_ =~ s/^\.//; $_} @path if $this->{hideEmpty};

  # rebuild normalized resource
  $resource = join("/", @path);

  # get web part
  my $web = '';
  while (@path) {
    last if $web && Foswiki::Func::topicExists($web, $path[0]);
    if (Foswiki::Func::webExists($web)) {
      my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($web);
      last if $path[0] eq NOCAT || $path[0] eq NOTAG || $path[0]=~ /^[[:lower:]]/ || $hierarchy->getCategory($path[0]);
    }
    $web .= ($web ? '/' : '') . shift(@path);
  }

  my %info = (
    type => 'R',
    web => $web,
    resource => $resource,
  );

  if (Foswiki::Func::webExists($web)) {
    my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($web);

    my $branch = shift(@path);

    if ($branch eq '00.topics') {
      # nop
    } elsif ($branch eq '01.categories') {

      # get category part
      my $catPath = '';
      my $cat = '';
      while (@path && ($path[0] eq NOCAT || $hierarchy->getCategory($path[0]))) {
        $cat = shift(@path);
        $catPath = ($catPath ? '/' : '') . $cat;
      }
      $info{category} = $cat if $cat;

    } elsif ($branch eq '02.tags') {

      # get tags part
      my $tagPath = '';
      # TODO
    }
  }

  # get topic part
  $info{topic} = shift(@path) if Foswiki::Func::topicExists($web, $path[0]);

  # get attachment part
  $info{attachment} = shift(@path);

  # anything else is an error
  return undef if scalar(@path);

  # derive type from found resources and rebuild path
  @path = ();
  if ($info{web}) {
    push @path, $info{web};

    if ($info{category}) {
      push @path, $catPath;
      $info{type} = 'C';
    } else {
      $info{type} = 'W';
    }

    if ($info{topic}) {
      push @path, $info{topic};
      $info{type} = 'D';
    }

    if ($info{attachment}) {
      push @path, $info{attachment};
      $info{type} = 'A';
    } 
  }

  # init topic for compatibility with upper level
  $info{topic} ||= $info{category};

  $info{path} = join("/", @path);

  #print STDERR dump(\%info)."\n";

  return \%info;
}

sub _W_list {
  my ($this, $info) = @_;

  return $this->_fail(POSIX::ENOENT, $info) unless Foswiki::Func::webExists($info->{web});
  return $this->_fail(POSIX::EACCES, $info) unless $this->_haveAccess('VIEW', $info->{web});

  my @list = ();

  foreach my $sweb (Foswiki::Func::getListOfWebs('user,public')) {
    next if $sweb eq $info->{web};
    next unless $sweb =~ s/^$info->{web}\/+//;
    next if $sweb =~ m#/#;
    push(@list, $sweb);
  }

  push @list '00.topics', '01.categories', '03.tags', '.', '..';

  return \@list;
}

1;
