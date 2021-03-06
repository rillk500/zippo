module zutility;

// std.zip functionality that is used
import std.zip: ZipArchive, ArchiveMember, CompressionMethod;

/* lists zip file contents
    in:
        const string filename => path to the *.zip including the zip file itself
*/
void listZipContents(const string filename = null) {
    import std.stdio: writef, readln;
    import std.file: exists, read;
    import std.conv: to;

    // check if file exists
    if(!filename.exists) {
        writef("\n%s%s%s\n\n", "# error: Zip file <", filename, "> does not exist!");
        return;
    }

    // read zip file into memory
    ZipArchive zip = new ZipArchive(read(filename));
    
    // print the number of files in a zip file
    // ask the user whether to print the contents of the zip or not
    writef("\n<%s> contains %s files. Show them all? (y/n): ", filename, zip.directory.length);

    if((readln()[0]) == 'y') { 
        // iterate over all zip members
        writef("%10s\t%s\n", "Size", "Name");
        foreach(file, data; zip.directory) {
            // print some info about each member
            string fileSize = (
                (data.expandedSize > 1_000_000_000) ? ((data.expandedSize.to!float / 1_000_000_000).to!string ~ " Gb") : (
                    (data.expandedSize > 1_000_000) ? ((data.expandedSize.to!float / 1_000_000).to!string ~ " Mb") : (
                        (data.expandedSize > 1_000) ? ((data.expandedSize.to!float / 1_000).to!string ~ " Kb") : (
                            data.expandedSize.to!string ~ "  b"
                        )
                    )
                )
            );
            
            writef("%10s\t%s\n", fileSize, file);
        }
    } else {
        writef("%s\n", "# error: Canceled...");
    }

    writef("\n");
}

/* unzips the zip file (or the specified files only contained in a zip)
    in:
	   const string filename    => path to the *.zip including the zip file itself
       const string[] files     => files to unzip, if none are specified, unzips all
       const string[] fignore   => files to exclude from decompression
       const bool verbose       => verbose output
*/
void decompress(const string filename = null, const string[] files = null, const string[] fignore = null, const bool verbose = false) {
    import std.stdio: writef;
    import std.file: isDir, exists, read, write, mkdirRecurse;
    import std.path: dirSeparator;
    import std.array: array;
    import std.conv: to;
    import std.algorithm.searching: canFind;
    import std.algorithm.mutation: remove;
    import std.parallelism: parallel;

    // check if file exists
    if(!filename.exists) {
        writef("\n%s%s%s\n\n", "# error: Zip file <", filename, "> does not exist!");
        return;
    }

    // read a zip file into memory
    ZipArchive zip = new ZipArchive(read(filename));
   
    // create the directory structure as in the zip file
    foreach(file, data; zip.directory) {
        if(file[$-1] == dirSeparator.to!char) {
            mkdirRecurse(file);
        }
    }

    // unzip all files
    if(files is null) {
        if(fignore is null) {
	        foreach(pair; zip.directory.byKeyValue.parallel) {
	            // skip empty directories
	            if(pair.key[$-1] == dirSeparator.to!char) { continue; }
	
	            // decompress the archive member
	            pair.key.write(zip.expand(pair.value));    
	    
	            // verbose output
	            if(verbose) {
                    writef("Decompressed: %s\n", pair.key);
	            }
            }
            
            // verbose output
            if(verbose) {
                writef("\nINFO: %s files decompressed.\n", zip.totalEntries);
            }
        } else { // unzip all files except for files that should be ignored
            // remove files that sould be ignored
            auto ufiles = zip.directory.byKeyValue.array;
            foreach(fi; fignore) {
                ufiles = ufiles.remove!(a => a.key.canFind(fi));
            }

            foreach(pair; ufiles.parallel) {
	            // skip empty directories
                if(pair.key[$-1] == dirSeparator.to!char) { continue; }
                    
                // decompress the archive member
    		    pair.key.write(zip.expand(pair.value));
        	    
    	        // verbose output
    	        if(verbose) {
    		        writef("Decompressed: %s\n", pair.key);
        		}
            }

            // verbose output
            if(verbose) {
                writef("\nINFO: %s files decompressed.\n", ufiles.length);
            }
        }
    } else { // unzip specified files only
        // remove all files that we do not need
        auto ufiles = zip.directory.byKeyValue.array;
        foreach(file; files.parallel) {
            ufiles = ufiles.remove!(a => !a.key.canFind(file));
        }

        foreach(pair; ufiles.parallel) {
            // skip empty directories
            if(pair.key[$-1] == dirSeparator.to!char) { continue; }

            // decompress the archive member
    		pair.key.write(zip.expand(pair.value));
            
            // verbose output
            if(verbose) {
    		    writef("Unzipped: %s\n", pair.key);
    		}
        }

        // verbose output
        if(verbose) {
            writef("\nINFO: %s files decompressed.\n", ufiles.length);
        }
    }
    
    writef("\n");
}

/* compresses files in a specified directory into a single zip file,
    if the directory is not specified, uses the current working directory
    in:
        const string filename   => zip file name
        const string path       => path to a file or to a directory
        const string[] files    => files to zip, if none are specified, zips all files
        const string[] fignore  => files exclude from compression
        const bool verbose      => verbose output
*/
void compress(string filename = null, string path = null, const string[] files = null, const string[] fignore = null, const bool verbose = false) {
    import std.stdio: writef;
    import std.file: write, exists, getcwd, isDir;
    import std.path: dirSeparator;
    import std.parallelism: parallel;
    import std.algorithm.mutation: remove;
    import std.algorithm.searching: canFind;

    // default file name
    if(filename is null) { filename = "archive.zip"; }

    // check if path is specified
    if(path is null) {
        path = getcwd ~ dirSeparator;
    } else {
        // check if path exists
        if(!path.exists) {
            writef("\n%s%s%s\n\n", "# ==> error: Path <", path, "> does not exist!");
            return;
        }
    }

    // compress everyting in cwd
    if(files is null) {
        if(fignore is null) { // compress all files
            compressAll(filename, path, verbose);
        } else { // compress all files, except for files that should be ignored
            ignoreAndCompress(filename, path, fignore, verbose);
        }
    } else { // compress the specified files only
        // list dir contents
        string[] zfiles = path.listdir;

        // exclude files from compression 
        foreach(file; files.parallel) {
            zfiles = zfiles.remove!(a => !a.canFind(file));
        }

        // zip specified files only
        ZipArchive zip = new ZipArchive(); 
        zip.isZip64(true);

        foreach(file; zfiles.parallel) {
            // archive the file
            ArchiveMember member = new ArchiveMember();
            if(file.isDir) {
                member.name = file ~ dirSeparator;
            } else {
                member.name = file;
                member.expandedData(readFileData(file));
            }
            
            member.compressionMethod = CompressionMethod.deflate;
            zip.addMember(member);

            // verbose output
            if(verbose) {
                writef("Compressed: %s\n", file);
            }
        }

        if(zip.totalEntries > 0) {
            write(filename, zip.build());
        }

        // verbose output
        if(verbose) {
            writef("\nINFO: %s files compressed.", zip.totalEntries);
        }
    }

    writef("\n");
}

/* compresses all files in a specified directory into a single zip file,
    if the directory is not specified, uses the current working directory
    in:
        const string filename   => zip file name
        const string path       => path to a directory
        const bool verbose      => verbose output
*/
private void compressAll(const string filename = null, const string path = null, const bool verbose = false) {
    import std.stdio: writef;
    import std.file: write, isDir;
    import std.path: dirSeparator;
    import std.array: array;
    import std.conv: to;
    import std.algorithm.iteration: filter;
    import std.parallelism: parallel;

    // get all dir contents
    string[] files = path.listdir;
    
    // create a zip archive file
    ZipArchive zip = new ZipArchive(); 
    zip.isZip64(true);
    
    // zip files
    foreach(file; files.parallel) {
        ArchiveMember member = new ArchiveMember();
        if(file.isDir) {
            member.name = file ~ dirSeparator;
        } else {
            member.name = file;
            member.expandedData(readFileData(file));
        }

        member.compressionMethod = CompressionMethod.deflate;
        zip.addMember(member);

        // verbose output
        if(verbose) {
            writef("Compressed: %s\n", file);
        }
    }

 
    if(zip.totalEntries > 0) {
        write(filename, zip.build());
    }

    // verbose output
    if(verbose) {
        writef("\nINFO: %s files compressed.", zip.totalEntries);
    }
    
    writef("\n");
}

/* compresses all files in a directory excluding specified files; 
    if the directory is not specified, uses the current working directory
    in:
        const string filename   => zip file name
        const string path       => path to a file or to a directory
        const string[] fignore  => exclude files from compression
        const bool verbose      => verbose output
*/
void ignoreAndCompress(const string filename = null, string path = null, const string[] fignore = null, const bool verbose = false) {
    import std.stdio: writef;
    import std.file: write, isDir;
    import std.path: dirSeparator;
    import std.array: array;
    import std.algorithm.iteration: filter;
    import std.algorithm.searching: canFind;
    import std.algorithm.mutation: remove;
    import std.parallelism: parallel;

    // list dir contents
    string[] zfiles = path.listdir;

    // exclude files from compression entered by the user
    foreach(fi; fignore) {
        zfiles = zfiles.remove!(a => a.canFind(fi));
    }

    // zip specified files only
    ZipArchive zip = new ZipArchive(); 
    zip.isZip64(true);
    
    // zip files
    foreach(file; zfiles.parallel) {
        // archive the file
        ArchiveMember member = new ArchiveMember();
        if(file.isDir) {
            member.name = file ~ dirSeparator;
        } else {
            member.name = file;
            member.expandedData(readFileData(file));
        }

        member.compressionMethod = CompressionMethod.deflate;
        zip.addMember(member);

        // verbose output
        if(verbose) {
            writef("Compressed: %s\n", file);
        }
    }

    if(zip.totalEntries > 0) {
        write(filename, zip.build());
    }

    // verbose output
    if(verbose) {
        writef("\nINFO: %s files compressed.", zip.totalEntries);
    }

    writef("\n");
}

/* reads from a file and returns the data as ubyte[]
    in:
        const string filename
    out:
        ubyte[]
*/
ubyte[] readFileData(const string filename) {
    import std.stdio: writef, File;
    import std.file: exists;
    import std.conv: to;
    
    // check if file exists
    if(!filename.exists) {
        writef("%s%s%s\n", "# error: File <", filename, "> does not exist!");
        return [];
    }
    
    // open the file
    File file = File(filename, "r"); 
    scope(exit) { file.close(); }
    
    // read file data
    ubyte[] data;
    while(!file.eof) {
        data ~= file.readln;
    }

    return data;
}

/* lists all files in a directory
    in:
        const string path
    out:
        string[]
*/

string[] listdir(const string path = null) {
    import std.algorithm.iteration: map;
    import std.array: array;
    import std.file: dirEntries, SpanMode, getcwd;
    import std.path: baseName;

    return dirEntries(((path is null) ? (getcwd) : (path)), SpanMode.breadth)
        .map!(a => a.name)
        .array;
}

/* splits a string into multiple strings given a seperator
    in:
        const string str => string
        const string sep => seperator
    out:
        string[]
*/
string[] multipleSplit(const string str = "", const string sep = "") { 
    import std.algorithm: findSplit, canFind;

    string[] s;
    if(str.canFind(sep)) {
        auto temp = str.findSplit(sep);
        s ~= temp[0];
	
        s ~= temp[$-1].multipleSplit(sep);
    } else {
        s ~= str;
    }

    return s;
}
