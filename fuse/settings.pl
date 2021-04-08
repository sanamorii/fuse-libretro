#!/usr/bin/perl -w

# settings.pl: generate settings.c from settings.dat
# Copyright (c) 2002-2005 Philip Kendall

# $Id: settings.pl 4961 2013-05-19 05:17:30Z sbaldovi $

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Author contact information:

# E-mail: philip-fuse@shadowmagic.org.uk

use strict;

use Fuse;

sub hashline ($) { '#line ', $_[0] + 1, '"', __FILE__, "\"\n" }

my %options;

while(<>) {

    next if /^\s*$/;
    next if /^\s*#/;

    chomp;

    my( $name, $type, $default, $short, $commandline, $configfile ) =
	split /\s*,\s*/;

    if( not defined $commandline ) {
	$commandline = $name;
	$commandline =~ s/_/-/g;
    }

    if( not defined $configfile ) {
	$configfile = $commandline;
	$configfile =~ s/-//g;
    }

    $options{$name} = { type => $type, default => $default, short => $short,
			commandline => $commandline,
			configfile => $configfile };
}

print Fuse::GPL( 'settings.c: Handling configuration settings',
		 '2002 Philip Kendall' );

print hashline( __LINE__ ), << 'CODE';

/* This file is autogenerated from settings.dat by settings.pl.
   Do not edit unless you know what will happen! */

#include <config.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef HAVE_GETOPT_LONG		/* Did our libc include getopt_long? */
#include <getopt.h>
#elif defined AMIGA || defined __MORPHOS__            /* #ifdef HAVE_GETOPT_LONG */
/* The platform uses GNU getopt, but not getopt_long, so we get
   symbol clashes on this platform. Just use getopt */
#else				/* #ifdef HAVE_GETOPT_LONG */
#include "compat.h"		/* If not, use ours */
#endif				/* #ifdef HAVE_GETOPT_LONG */

#ifdef HAVE_LIB_XML2
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#endif				/* #ifdef HAVE_LIB_XML2 */

#include "fuse.h"
#include "machine.h"
#include "settings.h"
#include "spectrum.h"
#include "ui/ui.h"
#include "utils.h"

/* The name of our configuration file */
#ifdef WIN32
#define CONFIG_FILE_NAME "fuse.cfg"
#else				/* #ifdef WIN32 */
#define CONFIG_FILE_NAME ".fuserc"
#endif				/* #ifdef WIN32 */

/* The current settings of options, etc */
settings_info settings_current;

/* The default settings of options, etc */
settings_info settings_default = {
CODE

    foreach my $name ( sort keys %options ) {
	next if $options{$name}->{type} eq 'null';
	print "  /* $name */ $options{$name}->{default},\n";
    }

print hashline( __LINE__ ), << 'CODE';
  /* show_help */ 0,
  /* show_version */ 0,
};

static int read_config_file( settings_info *settings );

#ifdef HAVE_LIB_XML2
static int parse_xml( xmlDocPtr doc, settings_info *settings );
#else				/* #ifdef HAVE_LIB_XML2 */
static int parse_ini( utils_file *file, settings_info *settings );
#endif				/* #ifdef HAVE_LIB_XML2 */

static int settings_command_line( settings_info *settings, int *first_arg,
				  int argc, char **argv );

static void settings_copy_internal( settings_info *dest, settings_info *src );

/* Called on emulator startup */
int
settings_init( int *first_arg, int argc, char **argv )
{
  int error;

  settings_defaults( &settings_current );

  error = read_config_file( &settings_current );
  if( error ) return error;

  error = settings_command_line( &settings_current, first_arg, argc, argv );
  if( error ) return error;

  return 0;
}

/* Fill the settings structure with sensible defaults */
void settings_defaults( settings_info *settings )
{
  settings_copy_internal( settings, &settings_default );
}

#ifdef HAVE_LIB_XML2

/* Read options from the config file (if libxml2 is available) */

static int
read_config_file( settings_info *settings )
{
  const char *home; char path[ PATH_MAX ];
  struct stat stat_info;

  xmlDocPtr doc;

  home = compat_get_home_path(); if( !home ) return 1;

  snprintf( path, PATH_MAX, "%s/%s", home, CONFIG_FILE_NAME );

  /* See if the file exists; if doesn't, it's not a problem */
  if( stat( path, &stat_info ) ) {
    if( errno == ENOENT ) {
      return 0;
    } else {
      ui_error( UI_ERROR_ERROR, "couldn't stat '%s': %s", path,
		strerror( errno ) );
      return 1;
    }
  }

  doc = xmlParseFile( path );
  if( !doc ) {
    ui_error( UI_ERROR_ERROR, "error reading config file" );
    return 1;
  }

  if( parse_xml( doc, settings ) ) {
    xmlFreeDoc( doc );
    return 1;
  }

  xmlFreeDoc( doc );

  return 0;
}

static int
parse_xml( xmlDocPtr doc, settings_info *settings )
{
  xmlNodePtr node;
  xmlChar *xmlstring;

  node = xmlDocGetRootElement( doc );
  if( xmlStrcmp( node->name, (const xmlChar*)"settings" ) ) {
    ui_error( UI_ERROR_ERROR, "config file's root node is not 'settings'" );
    return 1;
  }

  node = node->xmlChildrenNode;
  while( node ) {

CODE

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};

    if( $type eq 'boolean' or $type eq 'numeric' ) {

	print << "CODE";
    if( !strcmp( (const char*)node->name, "$options{$name}->{configfile}" ) ) {
      xmlstring = xmlNodeListGetString( doc, node->xmlChildrenNode, 1 );
      if( xmlstring ) {
        settings->$name = atoi( (char*)xmlstring );
        xmlFree( xmlstring );
      }
    } else
CODE

    } elsif( $type eq 'string' ) {

	    print << "CODE";
    if( !strcmp( (const char*)node->name, "$options{$name}->{configfile}" ) ) {
      xmlstring = xmlNodeListGetString( doc, node->xmlChildrenNode, 1 );
      if( xmlstring ) {
        libspectrum_free( settings->$name );
        settings->$name = utils_safe_strdup( (char*)xmlstring );
        xmlFree( xmlstring );
      }
    } else
CODE

    } elsif( $type eq 'null' ) {

	    print << "CODE";
    if( !strcmp( (const char*)node->name, "$options{$name}->{configfile}" ) ) {
      /* Do nothing */
    } else
CODE

    } else {
	die "Unknown setting type `$type'";
    }
}

print hashline( __LINE__ ), << 'CODE';
    if( !strcmp( (const char*)node->name, "text" ) ) {
      /* Do nothing */
    } else {
      ui_error( UI_ERROR_WARNING, "Unknown setting '%s' in config file",
		node->name );
    }

    node = node->next;
  }

  return 0;
}

int
settings_write_config( settings_info *settings )
{
  const char *home; char path[ PATH_MAX ], buffer[80]; 

  xmlDocPtr doc; xmlNodePtr root;

  home = compat_get_home_path(); if( !home ) return 1;

  snprintf( path, PATH_MAX, "%s/%s", home, CONFIG_FILE_NAME );

  /* Create the XML document */
  doc = xmlNewDoc( (const xmlChar*)"1.0" );

  root = xmlNewNode( NULL, (const xmlChar*)"settings" );
  xmlDocSetRootElement( doc, root );
CODE

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};

    if( $type eq 'boolean' ) {

	print "  xmlNewTextChild( root, NULL, (const xmlChar*)\"$options{$name}->{configfile}\", (const xmlChar*)(settings->$name ? \"1\" : \"0\") );\n";

    } elsif( $type eq 'string' ) {
	print << "CODE";
  if( settings->$name )
    xmlNewTextChild( root, NULL, (const xmlChar*)"$options{$name}->{configfile}", (const xmlChar*)settings->$name );
CODE
    } elsif( $type eq 'numeric' ) {
	print << "CODE";
  snprintf( buffer, 80, "%d", settings->$name );
  xmlNewTextChild( root, NULL, (const xmlChar*)"$options{$name}->{configfile}", (const xmlChar*)buffer );
CODE
    } elsif( $type eq 'null' ) {
	# Do nothing
    } else {
	die "Unknown setting type `$type'";
    }
}

  print hashline( __LINE__ ), << 'CODE';

  xmlSaveFormatFile( path, doc, 1 );

  xmlFreeDoc( doc );

  return 0;
}

#else				/* #ifdef HAVE_LIB_XML2 */

/* Read options from the config file as ini file (if libxml2 is not available) */

static int
read_config_file( settings_info *settings )
{
  const char *home; char path[ PATH_MAX ];
  struct stat stat_info;
  int error;

  utils_file file;

  home = compat_get_home_path(); if( !home ) return 1;

  snprintf( path, PATH_MAX, "%s/%s", home, CONFIG_FILE_NAME );

  /* See if the file exists; if doesn't, it's not a problem */
  if( stat( path, &stat_info ) ) {
    if( errno == ENOENT ) {
      return 0;
    } else {
      ui_error( UI_ERROR_ERROR, "couldn't stat '%s': %s", path,
		strerror( errno ) );
      return 1;
    }
  }

  error = utils_read_file( path, &file );
  if( error ) {
    ui_error( UI_ERROR_ERROR, "error reading config file" );
    return 1;
  }

  if( parse_ini( &file, settings ) ) { utils_close_file( &file ); return 1; }

  utils_close_file( &file );

  return 0;
}

static int
settings_var( settings_info *settings, unsigned char *name, unsigned char *last,
              int **val_int, char ***val_char, unsigned char **next  )
{
  unsigned char* cpos;
  size_t n;

  *val_int = NULL;
  *val_char = NULL;

  *next = name;
  while( name < last && ( *name == ' ' || *name == '\t' || *name == '\r' ||
                          *name == '\n' ) ) {
    *next = ++name;					/* seek to first char */
  }
  cpos = name;

  while( cpos < last && ( *cpos != '=' && *cpos != ' ' && *cpos != '\t' &&
                          *cpos != '\r' && *cpos != '\n' ) ) cpos++;
  *next = cpos;
  n = cpos - name;		/* length of name */

  while( *next < last && **next != '=' ) {		/* search for '=' */
    if( **next != ' ' && **next != '\t' && **next != '\r' && **next != '\n' )
      return 1;	/* error in value */
    (*next)++;
  }
  if( *next < last) (*next)++;		/* set after '=' */
/*  ui_error( UI_ERROR_WARNING, "Config: (%5s): ", name ); */

CODE
my %type = ('null' => 0, 'boolean' => 1, 'numeric' => 1, 'string' => 2 );
foreach my $name ( sort keys %options ) {
    my $len = length $options{$name}->{configfile};

    print << "CODE";
  if( n == $len && !strncmp( (const char *)name, "$options{$name}->{configfile}", n ) ) {
CODE
    print "    *val_int = \&settings->$name;\n" if( $options{$name}->{type} eq 'boolean' or $options{$name}->{type} eq 'numeric' );
    print "    *val_char = \&settings->$name;\n" if( $options{$name}->{type} eq 'string' );
    print "/*    *val_null = \&settings->$name; */\n" if( $options{$name}->{type} eq 'null' );
    print << "CODE";
    return 0;
  }
CODE
}
    print << "CODE";
  return 1;
}

static int
parse_ini( utils_file *file, settings_info *settings )
{
  unsigned char *cpos, *cpos_new;
  int *val_int;
  char **val_char;

  cpos = file->buffer;

  /* Read until the end of file */
  while( cpos < file->buffer + file->length ) {
    if( settings_var( settings, cpos, file->buffer + file->length, &val_int,
                      &val_char, &cpos_new ) ) {
      /* error in name or something else ... */
      cpos = cpos_new + 1;
      ui_error( UI_ERROR_WARNING,
                "Unknown and/or invalid setting '%s' in config file", cpos );
      continue;
    }
    cpos = cpos_new;
    if( val_int ) {
	*val_int = atoi( (char *)cpos );
	while( cpos < file->buffer + file->length && 
		( *cpos != '\\0' && *cpos != '\\r' && *cpos != '\\n' ) ) cpos++;
    } else if( val_char ) {
	char *value = (char *)cpos;
	size_t n = 0;
	while( cpos < file->buffer + file->length && 
		( *cpos != '\\0' && *cpos != '\\r' && *cpos != '\\n' ) ) cpos++;
	n = (char *)cpos - value;
	if( n > 0 ) {
	  if( *val_char != NULL ) {
	    libspectrum_free( *val_char );
	    *val_char = NULL;
	  }
	  *val_char = libspectrum_malloc( n + 1 );
	  (*val_char)[n] = '\\0';
	  memcpy( *val_char, value, n );
	}
    }
    /* skip 'new line' like chars */
    while( ( cpos < ( file->buffer + file->length ) ) &&
           ( *cpos == '\\r' || *cpos == '\\n' ) ) cpos++;

CODE
print hashline( __LINE__ ), << 'CODE';
  }

  return 0;
}

static int
settings_file_write( compat_fd fd, const char *buffer, size_t length )
{
  return compat_file_write( fd, (const unsigned char *)buffer, length );
}

static int
settings_string_write( compat_fd doc, const char* name, const char* config )
{
  if( config != NULL &&
      ( settings_file_write( doc, name, strlen( name ) ) ||
        settings_file_write( doc, "=", 1 ) ||
        settings_file_write( doc, config, strlen( config ) ) ||
        settings_file_write( doc, "\n", 1 ) ) )
    return 1;
  return 0;
}

static int
settings_boolean_write( compat_fd doc, const char* name, int config )
{
  return settings_string_write( doc, name, config ? "1" : "0" );
}

static int
settings_numeric_write( compat_fd doc, const char* name, int config )
{
  char buffer[80]; 
  snprintf( buffer, sizeof( buffer ), "%d", config );
  return settings_string_write( doc, name, buffer );
}

int
settings_write_config( settings_info *settings )
{
  const char *home; char path[ PATH_MAX ];

  compat_fd doc;

  home = compat_get_home_path(); if( !home ) return 1;

  snprintf( path, PATH_MAX, "%s/%s", home, CONFIG_FILE_NAME );

  doc = compat_file_open( path, 1 );
  if( doc == COMPAT_FILE_OPEN_FAILED ) {
    ui_error( UI_ERROR_ERROR, "couldn't open `%s' for writing: %s\n",
	      path, strerror( errno ) );
    return 1;
  }

CODE

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};
    my $len = length "$options{$name}->{configfile}";

    if( $type eq 'boolean' ) {

	print << "CODE";
  if( settings_boolean_write( doc, "$options{$name}->{configfile}",
                              settings->$name ) )
    goto error;
CODE

    } elsif( $type eq 'string' ) {
	print << "CODE";
  if( settings_string_write( doc, "$options{$name}->{configfile}",
                             settings->$name ) )
    goto error;
CODE

    } elsif( $type eq 'numeric' ) {
	print << "CODE";
  if( settings_numeric_write( doc, "$options{$name}->{configfile}",
                              settings->$name ) )
    goto error;
CODE

    } elsif( $type eq 'null' ) {
	# Do nothing
    } else {
	die "Unknown setting type `$type'";
    }
}

  print hashline( __LINE__ ), << 'CODE';

  compat_file_close( doc );

  return 0;
error:
  compat_file_close( doc );

  return 1;
}

#endif				/* #ifdef HAVE_LIB_XML2 */

/* Read options from the command line */
static int
settings_command_line( settings_info *settings, int *first_arg,
                       int argc, char **argv )
{
#ifdef GEKKO
  /* No argv on the Wii. Just return */
  return 0;
#endif

#if !defined AMIGA && !defined __MORPHOS__

  struct option long_options[] = {

CODE

my $fake_short_option = 256;

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};
    my $commandline = $options{$name}->{commandline};
    my $short = $options{$name}->{short};

    unless( $type eq 'boolean' or $short ) { $short = $fake_short_option++ }

    if( $type eq 'boolean' ) {

	print << "CODE";
    {    "$commandline", 0, &(settings->$name), 1 },
    { "no-$commandline", 0, &(settings->$name), 0 },
CODE
    } elsif( $type eq 'string' or $type eq 'numeric' ) {

	print "    { \"$commandline\", 1, NULL, $short },\n";
    } elsif( $type eq 'null' ) {
	# Do nothing
    } else {
	die "Unknown setting type `$type'";
    }
}

print hashline( __LINE__ ), << 'CODE';

    { "help", 0, NULL, 'h' },
    { "version", 0, NULL, 'V' },

    { 0, 0, 0, 0 }		/* End marker: DO NOT REMOVE */
  };

#endif      /* #ifndef AMIGA */

  while( 1 ) {

    int c;

#if defined AMIGA || defined __MORPHOS__
    c = getopt( argc, argv, "d:hm:o:p:f:r:s:t:v:g:j:V" );
#else                    /* #ifdef AMIGA */
    c = getopt_long( argc, argv, "d:hm:o:p:f:r:s:t:v:g:j:V", long_options, NULL );
#endif                   /* #ifdef AMIGA */

    if( c == -1 ) break;	/* End of option list */

    switch( c ) {

    case 0: break;	/* Used for long option returns */

CODE

$fake_short_option = 256;

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};
    my $short = $options{$name}->{short};

    unless( $type eq 'boolean' or $short ) { $short = $fake_short_option++ }

    if( $type eq 'boolean' ) {
	# Do nothing
    } elsif( $type eq 'string' ) {
	print "    case $short: settings_set_string( &settings->$name, optarg ); break;\n";
    } elsif( $type eq 'numeric' ) {
	print "    case $short: settings->$name = atoi( optarg ); break;\n";
    } elsif( $type eq 'null' ) {
	# Do nothing
    } else {
	die "Unknown setting type `$type'";
    }
}

print hashline( __LINE__ ), << 'CODE';

    case 'h': settings->show_help = 1; break;
    case 'V': settings->show_version = 1; break;

    case ':':
    case '?':
      break;

    default:
      fprintf( stderr, "%s: getopt_long returned `%c'\n",
	       fuse_progname, (char)c );
      break;

    }
  }

  /* Store the location of the first non-option argument */
  *first_arg = optind;

  return 0;
}

/* Copy one settings object to another */
static void
settings_copy_internal( settings_info *dest, settings_info *src )
{
  settings_free( dest );

CODE

foreach my $name ( sort keys %options ) {

    my $type = $options{$name}->{type};

    if( $type eq 'boolean' or $type eq 'numeric' ) {
	print "  dest->$name = src->$name;\n";
    } elsif( $type eq 'string' ) {
	print << "CODE";
  dest->$name = NULL;
  if( src->$name ) {
    dest->$name = utils_safe_strdup( src->$name );
  }
CODE
    }
}

print hashline( __LINE__ ), << 'CODE';
}

/* Copy one settings object to another */
void settings_copy( settings_info *dest, settings_info *src )
{
  settings_defaults( dest );
  settings_copy_internal( dest, src );
}

char **
settings_get_rom_setting( settings_info *settings, size_t which )
{
  switch( which ) {
  case  0: return &( settings->rom_16       );
  case  1: return &( settings->rom_48       );
  case  2: return &( settings->rom_128_0    );
  case  3: return &( settings->rom_128_1    );
  case  4: return &( settings->rom_plus2_0  );
  case  5: return &( settings->rom_plus2_1  );
  case  6: return &( settings->rom_plus2a_0 );
  case  7: return &( settings->rom_plus2a_1 );
  case  8: return &( settings->rom_plus2a_2 );
  case  9: return &( settings->rom_plus2a_3 );
  case 10: return &( settings->rom_plus3_0  );
  case 11: return &( settings->rom_plus3_1  );
  case 12: return &( settings->rom_plus3_2  );
  case 13: return &( settings->rom_plus3_3  );
  case 14: return &( settings->rom_plus3e_0 );
  case 15: return &( settings->rom_plus3e_1 );
  case 16: return &( settings->rom_plus3e_2 );
  case 17: return &( settings->rom_plus3e_3 );
  case 18: return &( settings->rom_tc2048   );
  case 19: return &( settings->rom_tc2068_0 );
  case 20: return &( settings->rom_tc2068_1 );
  case 21: return &( settings->rom_ts2068_0 );
  case 22: return &( settings->rom_ts2068_1 );
  case 23: return &( settings->rom_pentagon_0 );
  case 24: return &( settings->rom_pentagon_1 );
  case 25: return &( settings->rom_pentagon_2 );
  case 26: return &( settings->rom_pentagon512_0 );
  case 27: return &( settings->rom_pentagon512_1 );
  case 28: return &( settings->rom_pentagon512_2 );
  case 29: return &( settings->rom_pentagon512_3 );
  case 30: return &( settings->rom_pentagon1024_0 );
  case 31: return &( settings->rom_pentagon1024_1 );
  case 32: return &( settings->rom_pentagon1024_2 );
  case 33: return &( settings->rom_pentagon1024_3 );
  case 34: return &( settings->rom_scorpion_0 );
  case 35: return &( settings->rom_scorpion_1 );
  case 36: return &( settings->rom_scorpion_2 );
  case 37: return &( settings->rom_scorpion_3 );
  case 38: return &( settings->rom_spec_se_0 );
  case 39: return &( settings->rom_spec_se_1 );
  case 40: return &( settings->rom_interface_i );
  case 41: return &( settings->rom_beta128 );
  case 42: return &( settings->rom_plusd );
  case 43: return &( settings->rom_disciple );
  case 44: return &( settings->rom_opus );
  case 45: return &( settings->rom_speccyboot );
  default: return NULL;
  }
}

void
settings_set_string( char **string_setting, const char *value )
{
  /* No need to do anything if the two strings are in fact the
     same pointer */
  if( *string_setting == value ) return;

  if( *string_setting ) libspectrum_free( *string_setting );
  *string_setting = utils_safe_strdup( value );
}

int
settings_free( settings_info *settings )
{
CODE

foreach my $name ( sort keys %options ) {
    if( $options{$name}->{type} eq 'string' ) {
	print "  if( settings->$name ) libspectrum_free( settings->$name );\n";
    }
}

print hashline( __LINE__ ), << 'CODE';

  return 0;
}

int
settings_end( void )
{
  if( settings_current.autosave_settings )
    settings_write_config( &settings_current );

  settings_free( &settings_current );

#ifdef HAVE_LIB_XML2
  xmlCleanupParser();
#endif				/* #ifdef HAVE_LIB_XML2 */

  return 0;
}
CODE
