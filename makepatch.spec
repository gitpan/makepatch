Summary: makepatch -- generate and apply patch kits
Name: makepatch
Version: 2.04
Release: 1
License: GPL or Perl Artistic
Distribution: Free
Group: Utilities/Text
Source: ftp://ftp.perl.org/pub/CPAN/authors/id/JV/%{name}-%{version}.tar.gz
#Patch: 
Requires: perl >= 5.004
#Prereq: 
Prefix: /usr/bin
Packager: Johan Vromans <jvromans@squirrel.nl>
Vendor: Squirrel Consultancy, Exloo, The Netherlands
BuildArch: noarch
BuildRoot: /var/tmp/makepatch-buildroot

%description
This is the makepatch package, containing a pair of programs to assist
in the generation and application of patch kits to synchronise source
trees.

The makepatch package contains two programs, both written in Perl:
'makepatch' and 'applypatch'.

'makepatch' will generate a patch kit from two source trees. 
It traverses the source directory and runs a 'diff' on each pair of
corresponding files, accumulating the output into a patch kit. It
knows about the conventions for patch kits: if a file named
patchlevel.h exists, it is handled first, so 'patch' can check the
version of the source tree. Also, to deal with the non-perfect
versions of 'patch' that are in use, it supplies 'Index:' and
'Prereq:' lines, so 'patch' can correctly locate the files to patch,
and it relocates the patch to the current directory to avoid problems
with creating new files.

The list of files can be specified in a so called 'manifest' file, but
it can also be generated by recursively traversing the source tree.
Files can be excluded using shell style wildcards and Perl regex
patterns.

Moreover, 'makepatch' prepends a small shell script in front of the
patch kit that creates the necessary files and directories for the
patch process. By running the patch kit as a shell script your source
directory is prepared for the patching process.

But that is not it! 'makepatch' also inserts some additional
information in the patch kit for use by the 'applypatch' program.

The 'applypatch' program will do the following:

  - It will extensively verify that the patch kit is complete and not
    corrupted during transfer.
  - It will apply some heuristics to verify that the directory in
    which the patch will be applied does indeed contain the expected
    sources.
  - It creates files and directories as necessary.
  - It applies the patch by running the 'patch' program.
  - Upon completion, obsolete files, directories and .orig files are
    removed, file modes of new files are set, and the timestamps of
    all patched files are adjusted.

Note that 'applypatch' only requires the 'patch' program. It does not
rely on a shell or shell tools. This makes it possible to apply
patches on non-Unix systems.

%prep
%setup
#%patch -p0 -b .opt

%build
perl Makefile.PL
make all
make test

%install
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man1
install blib/script/makepatch $RPM_BUILD_ROOT%{_bindir}
install blib/script/applypatch $RPM_BUILD_ROOT%{_bindir}
install -m 0444 blib/man1/* $RPM_BUILD_ROOT%{_mandir}/man1

%files
%doc README CHANGES
%{_bindir}/*
%{_mandir}/man1/*

