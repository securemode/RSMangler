#!/usr/bin/env ruby
#encoding: UTF-8
#
# == RSMangler: Take a wordlist and mangle it
#
# RSMangler will take a wordlist and perform various manipulations on it similar to
# those done by John the Ripper with a few extras, the main one being permutations mode
# which takes each word in the list and combines it with the others to produce all
# possible permutations (not combinations, order matters).
#
# See the README for full information
#
# Original Author:: Robin Wood (robin@digi.ninja)
# Version:: 1.5 alpha
# Copyright:: Copyright(c) 2017 Robin Wood - https://digi.ninja
# Licence:: Creative Commons Attribution-Share Alike 2.0
#
# Changes:
# 1.5 alpha - Working on writing straight to disk rather than to STDOUT
# 1.4 - Added full leetspeak option, thanks Felipe Molina (@felmoltor)
#

require 'date'
require 'getoptlong'
require 'zlib'

# The left hand character is what you are looking for
# and the right hand array is the one you are replacing it
# with

leet_swap = {
	's' => ['$', '5', 's'],
	'e' => ['3', 'e'],
	'a' => ['4', '@', 'a'],
	'o' => ['0', 'o'],
	'i' => ['1', 'i'],
	'l' => ['1', 'l'],
	't' => ['7', 't'],
	'b' => ['8', 'b'],
	'z' => ['2', 'z'],
}

# Common words to append and prepend if --common is allowed

common_words = [
	'pw',
	'pwd',
	'admin',
	'pass'
]

opts = GetoptLong.new(
	['--help', '-h', GetoptLong::NO_ARGUMENT],
	['--file', '-f', GetoptLong::REQUIRED_ARGUMENT],
	['--output', '-o', GetoptLong::REQUIRED_ARGUMENT],
	['--min', '-m', GetoptLong::REQUIRED_ARGUMENT],
	['--max', '-x', GetoptLong::REQUIRED_ARGUMENT],
	['--perms', '-p', GetoptLong::NO_ARGUMENT],
	['--double', '-d', GetoptLong::NO_ARGUMENT],
	['--reverse', '-r', GetoptLong::NO_ARGUMENT],
	['--leet', '-t', GetoptLong::NO_ARGUMENT],
	['--full-leet', '-T', GetoptLong::NO_ARGUMENT],
	['--capital', '-c', GetoptLong::NO_ARGUMENT],
	['--upper', '-u', GetoptLong::NO_ARGUMENT],
	['--lower', '-l', GetoptLong::NO_ARGUMENT],
	['--swap', '-s', GetoptLong::NO_ARGUMENT],
	['--ed', '-e', GetoptLong::NO_ARGUMENT],
	['--ing', '-i', GetoptLong::NO_ARGUMENT],
	['--punctuation', GetoptLong::NO_ARGUMENT],
	['--years', '-y', GetoptLong::NO_ARGUMENT],
	['--months', '-n', GetoptLong::NO_ARGUMENT],
	['--welcome', '-w', GetoptLong::NO_ARGUMENT],
	['--acronym', '-a', GetoptLong::NO_ARGUMENT],
	['--seasons', GetoptLong::NO_ARGUMENT],
	['--random', GetoptLong::NO_ARGUMENT],
	['--common', '-C', GetoptLong::NO_ARGUMENT],
	['--pnb', GetoptLong::NO_ARGUMENT],
	['--pna', GetoptLong::NO_ARGUMENT],
	['--nb', GetoptLong::NO_ARGUMENT],
	['--na', GetoptLong::NO_ARGUMENT],
	['--force', GetoptLong::NO_ARGUMENT],
	['--space', GetoptLong::NO_ARGUMENT],
	['--allow-duplicates', GetoptLong::NO_ARGUMENT],
	['-v', GetoptLong::NO_ARGUMENT]
)

def good_call
	puts
	puts 'Good call, either reduce the size of your word list or use the --perms option to disable permutations'
	puts
	exit
end

def leet_variations (str, swap)
  swap_all = Hash.new { |_,k| [k] }.merge(swap) 
  arr = swap_all.values_at(*str.chars)
  arr.shift.product(*arr).map(&:join)
end

# Display the usage
def usage
	puts 'rsmangler v 1.5 Robin Wood (robin@digi.ninja) <https://digi.ninja>

Basic usage:

	./rsmangler.rb --file wordlist.txt

To pass the initial words in on standard in do:

	cat wordlist.txt | ./rsmangler.rb

To send the output to a file:

	./rsmangler.rb --file wordlist.txt --output mangled.txt

	All options are ON by default, these parameters turn them OFF

	Usage: rsmangler.rb [OPTION]
	--help, -h: show help
	--file, -f: the input file, use - for STDIN
	--output, -o: the output file, use - for STDOUT
	--max, -x: maximum word length
	--min, -m: minimum word length
	--perms, -p: permutate all the words
	--double, -d: double each word
	--reverse, -r: reverser the word
	--leet, -t: l33t speak the word
	--full-leet, -T: all posibilities l33t
	--capital, -c: capitalise the word
	--upper, -u: uppercase the word
	--lower, -l: lowercase the word
	--swap, -s: swap the case of the word
	--ed, -e: add ed to the end of the word
	--ing, -i: add ing to the end of the word
	--punctuation: add common punctuation to the end of the word
	--years, -y: add all years from 1980 to 2020 year to start and end
	--months, -n: add all months from 1980 to 2020 year to start and end
	--welcome, -w: welcome
	--seasons: add SeasonYear from 1980 to 2020
	--random: Random additions
	--acronym, -a: create an acronym based on all the words entered in order and add to word list
	--common, -C: add the following words to start and end: admin, sys, pw, pwd
	--pna: add 01 - 09 to the end of the word
	--pnb: add 01 - 09 to the beginning of the word
	--na: add 1 - 123 to the end of the word
	--nb: add 1 - 123 to the beginning of the word
	--force: don\'t check output size
	--space: add spaces between words
	--allow-duplicates: allow duplicates in the output list

'

	exit
end

# The uniq_crcs array contains a crc of all words previously written,
# this should prevent duplicates being written out to the file
def puts_if_allowed(word)

	if not @max_length.nil? or not @min_length.nil?
		if not @min_length.nil?
			if word.length < @min_length
				return
			end
		end
		if not @max_length.nil?
			if word.length > @max_length
				return
			end
		end
	end

	if @deduplicate
		crc = Zlib::crc32(word)
		if not @uniq_crcs.include?(crc)
			@uniq_crcs << crc
			@output_handle.puts(word)
		end
	else
		@output_handle.puts(word)
	end
	@output_handle.flush
end

verbose = false
leet = true
full_leet = true
perms = true
double = true
reverse = true
capital = true
upper = true
lower = true
swap = true
ed = true
ing = true
punctuation = true
years = true
months = true
welcome = true
acronym = true
common = true
pna = true
pnb = true
na = true
nb = true
force = false
space = false
seasons = true
random = true
input_file_handle = nil
@min_length = nil
@max_length = nil
@deduplicate = true
@output_handle = STDOUT
@uniq_crcs = []
@debug = false

begin
	opts.each do |opt, arg|
		case opt
		when '--help'
			usage
		when '--output'
			if arg == '-'
				@output_handle = STDOUT
			else
				begin
					@output_handle = File.new(arg, 'w')
				rescue Errno::EACCES
					puts "Could not create the output file"
					exit
				end
			end
		when '--file'
			if arg == '-'
				input_file_handle = STDIN
			else
				if File.exist? arg
					input_file_handle = File.new(arg, 'r')
				else
					puts 'The specified file does not exist'
					exit
				end
			end
		when '--allow-duplicates'
			@deduplicate = false
		when '--max'
			@max_length = arg.to_i
		when '--min'
			@min_length = arg.to_i
		when '--leet'
			leet = false
		when '--full-leet'
			full_leet = false
		when '--perms'
			perms = false
		when '--double'
			double = false
		when '--reverse'
			reverse = false
		when '--capital'
			capital = false
		when '--upper'
			upper = false
		when '--lower'
			lower = false
		when '--swap'
			swap = false
		when '--ed'
			ed = false
		when '--ing'
			ing = false
		when '--common'
			common = false
		when '--acronym'
			acronym = false
		when '--years'
			years = false
		when '--months'
			months = false
		when '--welcome'
			welcome = false
		when '--seasons'
			seasons = false
		when '--random'
			random = false
		when '--punctuation'
			punctuation = false
		when '--pna'
			pna = false
		when '--pnb'
			pnb = false
		when '--na'
			na = false
		when '--nb'
			nb = false
		when '--space'
			space = true
		when '--force'
			force = true
		when '-v'
			verbose = true
		end
	end
rescue => e
	puts e
	usage
	exit
end

if input_file_handle.nil?
	puts 'No input file specified'
	puts
	usage
	exit
end

file_words = []

puts "Loading in the list" if @debug

while (word = input_file_handle.gets)
	file_words << word.chomp!
end

input_file_handle.close

if !force and perms and file_words.length > 5
	puts '5 words in a start list creates a dictionary of nearly 100,000 words.'
	puts 'You have ' + file_words.length.to_s + ' words in your list, are you sure you wish to continue?'
	puts 'Hit ctrl-c to abort'
	puts

	interrupted = false
	trap('INT') { interrupted = true }

	5.downto(1) do |i|
		print i.to_s + ' '
		STDOUT.flush
		sleep 1

		good_call if interrupted
	end

	good_call if interrupted
end

wordlist = []

if perms
	puts "Generating the permutations" if @debug
	for i in (1..file_words.length)
		file_words.permutation(i) do |c|
			perm = c.join
			wordlist << perm
			puts_if_allowed(perm)
		end
	end
else
	wordlist = file_words
end

puts "Permutations generated" if @debug

acro = nil

if acronym
	puts "Generating the acronyms" if @debug

	acro = ''
	file_words.each do |c|
		acro += c[0, 1]
	end
	puts_if_allowed(acro)
	wordlist << acro
end

puts "Doing the mangling" if @debug
wordlist.each do |x|
	results = []

	results << x + x
	results << x + x + "!"

	results << x.capitalize + x.capitalize
	results << x.capitalize + x.capitalize + "!"

		
	results << x.reverse
	results << x.reverse + "!"	

	results << x.capitalize
	results << x.capitalize + "!"
	
	results << x.downcase
	results << x.downcase + "!"
	
	results << x.upcase
	results << x.upcase + "!"
	
	results << x.swapcase
	results << x.swapcase + "!"

	if common
		common_words.each do |word|
			results << word + x
			results << x + word
		end
	end

	if full_leet
		leetarr = leet_variations(x, leet_swap)
		leetarr.each do |leetvar|
			results << leetvar
			results << leetvar + "!"
			results << leetvar.capitalize
			results << leetvar.capitalize + "!"
		end
	else
		# Only look at doing this if full leet is not enabled

		# Have to clone it otherwise the assignment is done
		# by reference and the gsub! updates both x and all_swapped
		all_swapped = x.clone
		if leet
			leet_swap.each_pair do |find, rep|
				all_swapped.gsub!(/#{find}/, rep)
				results << x.gsub(/#{find}/, rep)
			end
			results << all_swapped
		end
	end
	
	if punctuation
		for i in ('!@$%^&*()'.scan(/./))
			results << x + i.to_s
			results << x.capitalize + i.to_s
		end
	end

	if years
		for i in (1980..2020)
			results << i.to_s + x
			results << i.to_s + x + "!"
			
			results << x + i.to_s
			results << x + i.to_s + "!"
		
			results << i.to_s + x.capitalize	
			results << i.to_s + x.capitalize + "!"			
			
			results << x.capitalize + i.to_s
			results << x.capitalize + i.to_s + "!"
		end
	end

    if months
        for i in (1980..2020)
            results << i.to_s + "january"
            results << i.to_s + "january" + "!"
		
			results << i.to_s + "february"
			results << i.to_s + "february" + "!"

            results << i.to_s + "march"
            results << i.to_s + "march" + "!"

            results << i.to_s + "april"
            results << i.to_s + "april" + "!"

            results << i.to_s + "june"
            results << i.to_s + "june" + "!"

            results << i.to_s + "july"
            results << i.to_s + "july" + "!"

            results << i.to_s + "august"
            results << i.to_s + "august" + "!"

            results << i.to_s + "september"
            results << i.to_s + "september" + "!"

            results << i.to_s + "october"
            results << i.to_s + "october" + "!"

            results << i.to_s + "november"
            results << i.to_s + "november" + "!"

            results << i.to_s + "december"
            results << i.to_s + "december" + "!"


            results << i.to_s + "jan"
            results << i.to_s + "jan" + "!"

            results << i.to_s + "feb"
            results << i.to_s + "feb" + "!"

            results << i.to_s + "mar"
            results << i.to_s + "mar" + "!"

            results << i.to_s + "apr"
            results << i.to_s + "apr" + "!"

            results << i.to_s + "may"
            results << i.to_s + "may" + "!"

            results << i.to_s + "jun"
            results << i.to_s + "jun" + "!"

            results << i.to_s + "jul"
            results << i.to_s + "jul" + "!"

            results << i.to_s + "aug"
            results << i.to_s + "aug" + "!"

            results << i.to_s + "sep"
            results << i.to_s + "sep" + "!"

            results << i.to_s + "oct"
            results << i.to_s + "oct" + "!"

            results << i.to_s + "nov"
            results << i.to_s + "nov" + "!"

            results << i.to_s + "dec"
            results << i.to_s + "dec" + "!"


            results << "january" + i.to_s
            results << "january" + i.to_s + "!"

            results << "february" + i.to_s
            results << "february" + i.to_s + "!"

            results << "march" + i.to_s
            results << "march" + i.to_s + "!"

            results << "april" + i.to_s
            results << "april" + i.to_s + "!"

            results << "june" + i.to_s
            results << "june" + i.to_s + "!"

            results << "july" + i.to_s
            results << "july" + i.to_s + "!"

            results << "august" + i.to_s
            results << "august" + i.to_s + "!"

            results << "september" + i.to_s
            results << "september" + i.to_s + "!"

            results << "october" + i.to_s
            results << "october" + i.to_s + "!"

            results << "november" + i.to_s
            results << "november" + i.to_s + "!"

            results << "december" + i.to_s
            results << "december" + i.to_s + "!"


            results << "jan" + i.to_s
            results << "jan" + i.to_s + "!"

            results << "feb" + i.to_s
            results << "feb" + i.to_s + "!"

            results << "mar" + i.to_s
            results << "mar" + i.to_s + "!"

            results << "apr" + i.to_s
            results << "apr" + i.to_s + "!"

			results << "may" + i.to_s
			results << "may" + i.to_s + "!"


            results << "jun" + i.to_s
            results << "jun" + i.to_s + "!"

            results << "jul" + i.to_s
            results << "jul" + i.to_s + "!"

            results << "aug" + i.to_s
            results << "aug" + i.to_s + "!"

            results << "sep" + i.to_s
            results << "sep" + i.to_s + "!"

            results << "oct" + i.to_s
            results << "oct" + i.to_s + "!"

            results << "nov" + i.to_s
            results << "nov" + i.to_s + "!"

            results << "dec" + i.to_s
            results << "dec" + i.to_s + "!"

            results << i.to_s + "january".capitalize
            results << i.to_s + "january".capitalize + "!"

            results << i.to_s + "february".capitalize
            results << i.to_s + "february".capitalize + "!"

            results << i.to_s + "march".capitalize
            results << i.to_s + "march".capitalize + "!"

            results << i.to_s + "april".capitalize
            results << i.to_s + "april".capitalize + "!"

            results << i.to_s + "june".capitalize
            results << i.to_s + "june".capitalize + "!"

            results << i.to_s + "july".capitalize
            results << i.to_s + "july".capitalize + "!"

            results << i.to_s + "august".capitalize
            results << i.to_s + "august".capitalize + "!"

            results << i.to_s + "september".capitalize
            results << i.to_s + "september".capitalize + "!"

            results << i.to_s + "october".capitalize
            results << i.to_s + "october".capitalize + "!"

            results << i.to_s + "november".capitalize
            results << i.to_s + "november".capitalize + "!"

            results << i.to_s + "december".capitalize
            results << i.to_s + "december".capitalize + "!"



            results << i.to_s + "jan".capitalize
            results << i.to_s + "jan".capitalize + "!"

            results << i.to_s + "feb".capitalize
            results << i.to_s + "feb".capitalize + "!"

            results << i.to_s + "mar".capitalize
            results << i.to_s + "mar".capitalize + "!"

            results << i.to_s + "apr".capitalize
            results << i.to_s + "apr".capitalize + "!"

            results << i.to_s + "may".capitalize
            results << i.to_s + "may".capitalize + "!"

            results << i.to_s + "jun".capitalize
            results << i.to_s + "jun".capitalize + "!"

            results << i.to_s + "jul".capitalize
            results << i.to_s + "jul".capitalize + "!"

            results << i.to_s + "aug".capitalize
            results << i.to_s + "aug".capitalize + "!"

            results << i.to_s + "sep".capitalize
            results << i.to_s + "sep".capitalize + "!"

            results << i.to_s + "oct".capitalize
            results << i.to_s + "oct".capitalize + "!"

            results << i.to_s + "nov".capitalize
            results << i.to_s + "nov".capitalize + "!"

            results << i.to_s + "dec".capitalize
            results << i.to_s + "dec".capitalize + "!"

            results << "january".capitalize + i.to_s
            results << "january".capitalize + i.to_s + "!"

            results << "february".capitalize + i.to_s
            results << "february".capitalize + i.to_s + "!"

            results << "march".capitalize + i.to_s
            results << "march".capitalize + i.to_s + "!"

            results << "april".capitalize + i.to_s
            results << "april".capitalize + i.to_s + "!"

            results << "june".capitalize + i.to_s
            results << "june".capitalize + i.to_s + "!"

            results << "july".capitalize + i.to_s
            results << "july".capitalize + i.to_s + "!"

            results << "august".capitalize + i.to_s
            results << "august".capitalize + i.to_s + "!"

            results << "september".capitalize + i.to_s
            results << "september".capitalize + i.to_s + "!"

            results << "october".capitalize + i.to_s
            results << "october".capitalize + i.to_s + "!"

            results << "november".capitalize + i.to_s
            results << "november".capitalize + i.to_s + "!"

            results << "december".capitalize + i.to_s
            results << "december".capitalize + i.to_s + "!"

            results << "jan".capitalize + i.to_s
            results << "jan".capitalize + i.to_s + "!"

            results << "feb".capitalize + i.to_s
            results << "feb".capitalize + i.to_s + "!"

            results << "mar".capitalize + i.to_s
            results << "mar".capitalize + i.to_s + "!"

            results << "apr".capitalize + i.to_s
            results << "apr".capitalize + i.to_s + "!"

            results << "may".capitalize + i.to_s
            results << "may".capitalize + i.to_s + "!"

            results << "jun".capitalize + i.to_s
            results << "jun".capitalize + i.to_s + "!"
        
            results << "jul".capitalize + i.to_s
            results << "jul".capitalize + i.to_s + "!"

            results << "aug".capitalize + i.to_s
            results << "aug".capitalize + i.to_s + "!"

            results << "sep".capitalize + i.to_s
            results << "sep".capitalize + i.to_s + "!"

            results << "oct".capitalize + i.to_s
            results << "oct".capitalize + i.to_s + "!"

            results << "nov".capitalize + i.to_s
            results << "nov".capitalize + i.to_s + "!"

            results << "dec".capitalize + i.to_s
            results << "dec".capitalize + i.to_s + "!"

        end
    end

	if welcome
		nums = (0..20)
		for n in nums
			results << "welcome" + n.to_s
			results << "welcome" + n.to_s + "!"
			results << "welcome".capitalize + n.to_s
			results << "welcome".capitalize + n.to_s
		end
	end		

	if seasons
		season = ["winter","summer","spring","fall"]	
		years = (1980..2020)
		for i in season
			for y in years
				results << i.to_s + y.to_s
				results << i.to_s + y.to_s + "!"
				results << i.to_s.capitalize + y.to_s
				results << i.to_s.capitalize + y.to_s + "!"
			end
		end
	end

    if random
        word = ["qwerty","qwertyuiop","1qaz2wsx","qazwsx","asdfg","zxcvbnm","1234qwer","q1w2e3r4t5","qwer1234","q1w2e3r4","asdfasdf","qazwsxedc","asdfghjkl","q1w2e3","1qazxsw2","12QWaszx","qweasdzxc","mnbvcxz","a1b2c3d4","adgjmptw"]
        for i in word
            results << i.to_s
        end
    end

	if pna || pnb
		for i in (1..9)
			results << '0' + i.to_s + x if pnb
			results << '0' + i.to_s + x.capitalize
			results << '0' + i.to_s + x + "!" if pnb
			results << '0' + i.to_s + x.capitalize + "!" if pnb	

			results << x + '0' + i.to_s if pna
			results << x + '0' + i.to_s + "!" if pna
			results << x.capitalize + '0' + i.to_s if pna
			results << x.capitalize + '0' + i.to_s + "!" if pna
			
		end
	end

	if na || nb
		for i in (1..123)
			results << i.to_s + x if nb
			results << i.to_s + x + "!" if nb
			results << i.to_s + x.capitalize if nb
			results << i.to_s + x.capitalize + "!" if nb

			results << x + i.to_s if na
			results << x + i.to_s + "!" if na
			results << x.capitalize + i.to_s if na
			results << x.capitalize + i.to_s + "!" if na
		end
	end

    if na || nb
		
        results << x + "444" if nb
        results << x + "555" if nb
        results << x.capitalize + "444" if nb
        results << x.capitalize + "555" if nb

        results << x + "666" if nb
		results << x + "777" if nb
        results << x.capitalize + "666" if nb
		results << x.capitalize + "777" if nb

        results << x + "444" if na
        results << x + "555" if na
        results << x.capitalize + "444" if na
        results << x.capitalize + "555" if na

        results << x + "666" if na
		results << x + "777" if na
        results << x.capitalize + "666" if na
		results << x.capitalize + "777" if na
    end


	results.uniq!

	results.each do |res|
		puts_if_allowed(res)
	end
end
