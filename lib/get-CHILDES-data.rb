require 'find'
require 'sqlite3'
# require './corpus-file-info'
require './corpus-file-info-small'
require 'set'
require 'treetop'
require './mor'
require './chat'
require './data_reader'

CHILDES_DIRECTORY = "/home/jmu303/Documents/childes.psy.cmu.edu/data"

$verb_data = DataReader.hashonkeys_load('./verbs-CHILDES-SWBD.csv',[:Form,:Category], :CSV)

$verbs = {}
$verb_data.values.each do |x| $verbs[ x[:Form] ] = 1 end

$ages = Hash.new { |hash,key| hash[key] = Hash.new 0 }

$mismatches = File.open("mismatches.txt", 'w')

def to_tree(sn)
  #puts sn.struct.inspect if sn.respond_to?(:struct)
  case
  when sn.terminal? then sn.text_value
  else
    if sn.elements.all? {|e| e.terminal?}
    then (sn.elements.map {|e| e.text_value}).join('')
    else '(' + sn.extension_modules[0].to_s.sub(/.*::/,'') + " "+ sn.elements.map do |x|
        to_tree(x) if not x.empty?
      end.join(" ")  + ')'
    end
  end
end

$mor_parser = MorParser.new
$chat_parser = ChatParser.new

class CHILDESUtteranceMetadata
 attr_accessor :encoding, :participants, :languages, :situation, :warnings, :date, :comments, :birth, :location

  def initialize(metadata)
    @encoding = ""; @participants={}; @languages=[]; @situation = ""; @warnings=[]; @date = ""; @comments=[]; @birth ={}; @location=""

    metadata.each do |field|
      field.gsub!(/[\t]/," ")
      case field
      when /^@UTF8/ then
        @encoding = "utf8"
      when /^@Begin/ then
      when /^@Languages:/ then
        @languages = field.gsub(/^@Languages:/, "").strip
      when /^@Participants:/ then
        participants = field.gsub(/^@Participants:/, "").split(",").map {|x| x.strip}
        participants.each do |p|
          code, name, description = p.split.map {|x| x.strip}
          @participants[code] = {:Code => code, :Name => name, :Description => description}
        end
      when /^@ID:/ then
        language, corpus, code, age, sex, group, ses, role, education = field.gsub(/^@ID:/, "").split('|').map {|x| x.strip}
        @participants[code] = {} if @participants[code] == nil
        @participants[code].merge!({ :Language => language,
                                     :Corpus => corpus,
                                     :Age => age,
                                     :Sex => sex,
                                     :Group => group,
                                     :SES => ses,
                                     :Role => role,
                                     :Education => education})
      when /^@Media:/ then
      when /^@Situation:/ then @situation = field.gsub(/^@Situation:/, "").strip
      when /^@Warning:/ then @warnings = @warnings.push(field.gsub(/^@Warning:/, "").strip)
      when /^@Date:/ then @situation = field.gsub(/^@Situation:/, "").strip
      when /^@Comment:/ then  @comments = @comments.push(field.gsub(/^@Comment:/, "").strip)
      when /^@Tape Location:/ then
      when /^@G:/ then
      when /^@Birth of (...):/ then @birth[$1] = field.gsub(/^@Birth of (...):/, "").strip
      when /^@Time Start:/ then
      when /^@Location:/ then @location = field.gsub(/^@Location:/, "").strip
      when /^@Activities:/ then
      when /^@Time Duration:/ then
      when /^@Bg:/ then
      when /^@Bg/ then
      when /^@Eg:/ then
      when /^@Eg/ then
      when /^@New Episode/ then
      when /^@Transcriber:/ then
      when /^@Room Layout:/ then
      when /^@Color words:/ then
      when /^@Bck:/ then
      # Added by Jesse
      when /^@PID:/ then
      when /^@Font:/ then  # Not needed, only in Brown/Eve
      else raise "Unknown metadata field: #{field}" end
    end
  end

  def to_a
    a = []
    # Hash of instance variables
    vars = Hash[instance_variables.map { |name| [name, instance_variable_get(name)] } ]
    vars.each do |k, v|
      # FIXME do we just leave symbol keys alone?
      a.push({k => v})
    end
  end
end

def symbols_to_strings(hash)
  # Convert a possibly nested hash's keys to strings if not already.
  # Done here because I'm not sure if extending Hash is bad practice.
  return hash.to_s if not hash.is_a?(Hash) or hash.is_a?(Array)
  hash.each_with_object({}){|(k,v), h| h[k.to_s] = symbols_to_strings(v)}
end

def get_MOR_token_form(word_group)
  (word_group.map do |w|
    case
    when w[:Type]== :Punctuation then w[:Value]
    when w[:Type]== :PreClitic then w[:Word][:Stem]
    when w[:Type]== :Word then w[:Stem]
    when w[:Type]== :PostClitic then w[:Word][:Stem]
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:Stem] end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_category(word_group)
  #puts word_group.inspect
  (word_group.map do |w|
     #puts w.inspect
    case
    when w[:Type]== :Punctuation then "Punct"
    when w[:Type]== :PreClitic then w[:Word][:Pos][:Category]
    when w[:Type]== :Word then w[:Pos][:Category]
    when w[:Type]== :PostClitic then w[:Word][:Pos][:Category]
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:Pos][:Category] end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  #puts word_group.inspect
  (word_group.map do |w|
     #puts w.inspect
    case
    when w[:Type]== :Punctuation then "Punct"
    when w[:Type]== :PreClitic then w[:Word][:Pos][:SubCategories].join("|")
    when w[:Type]== :Word then w[:Pos][:SubCategories].join("|")
    when w[:Type]== :PostClitic then w[:Word][:Pos][:SubCategories].join("|")
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:Pos][:SubCategories].join("|") end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  #puts word_group.inspect
  (word_group.map do |w|
     #puts w.inspect
    case
    when w[:Type]== :Punctuation then "Punct"
    when w[:Type]== :PreClitic then w[:Word][:Pos][:SubCategories].join("|")
    when w[:Type]== :Word then w[:Pos][:SubCategories].join("|")
    when w[:Type]== :PostClitic then w[:Word][:Pos][:SubCategories].join("|")
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:Pos][:SubCategories].join("|") end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_fusionalsuffixes(word_group)
  #puts word_group.inspect
  (word_group.map do |w|
     #puts w.inspect
    case
    when w[:Type]== :Punctuation then "Punct"
    when w[:Type]== :PreClitic then w[:Word][:FusionalSuffixes].join("|") if w[:Word][:FusionalSuffixes]
    when w[:Type]== :Word then w[:FusionalSuffixes].join("|") if w[:FusionalSuffixes]
    when w[:Type]== :PostClitic then w[:Word][:FusionalSuffixes].join("|") if w[:FusionalSuffixes]
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:FusionalSuffixes].join("|")  if w[:FusionalSuffixes] end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_suffixes(word_group)
  #puts word_group.inspect
  (word_group.map do |w|
     #puts w.inspect
    case
    when w[:Type]== :Punctuation then "Punct"
    when w[:Type]== :PreClitic then w[:Word][:Suffixes].join("|") if w[:Word][:Suffixes]
    when w[:Type]== :Word then w[:Suffixes].join("|") if w[:Suffixes]
    when w[:Type]== :PostClitic then w[:Word][:Suffixes].join("|") if w[:Word][:Suffixes]
    when w[:Type]== :Compound then (w[:Parts].map do |p| p[:Suffixes].join("|") if w[:Suffixes] end).join('+')
    else raise "Can't handle this form!" end
  end).join('-')
end


$tiers = Hash.new 0
class CHILDESUtterance
  attr_accessor :num, :raw_utterance, :tokenized, :file_info, :speaker, :utterance_tokens, :annotations, :metadata, :corpus_metadata, :utterance_xml, :cleaned_utterance, :utterance_tokens, :age, :age_bin
  # New utterance
  def initialize(num, utterance, file_info, metadata, corpusMetadata)
    # Set metadata
    @tokenized = nil
    @num = num
    @file_info = file_info
    # Make metadata object from Array
    @metadata = CHILDESUtteranceMetadata.new(Array.new(metadata))
    # This is the metadata attached to the corpus file in parent directory
    @corpus_metadata = Array.new(corpusMetadata)

    # print "UTTERANCE: "; puts utterance
    # puts utterance
    # puts
    # puts
    tokens = utterance.first.split.map { |t| t.strip }
    # puts utterance
    # print "TOKENS:"; puts tokens
    @speaker= tokens[0].gsub(/[*:]/,"").strip
    # Get everything but first row
    @raw_utterance = tokens.slice(1..-1).join(" ").gsub(/[^ ],/, " ,") #we have to make a number of fixes to the raw data to get parsing to work

    # $mismatches.puts "Parsing: #{@raw_utterance}"
    # Parse chat format
    p = $chat_parser.parse(@raw_utterance)
    if p == nil
      $mismatches.puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
      puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
      $stdout.flush
    else
      # $mismatches.puts "Parsed:\n\t#{@raw_utterance}\n\t#{to_tree(p)}\n\t#{p.replace}"
      $stdout.flush
      # Couple of basic replacements
      @tokenized = p.replace.gsub(/ ta /," to ").gsub(/mhm/, "yes").split.map {|t| t.strip}
    end

    # @utterance_xml = ChildesAnnotation.convert_CHAT2xml( @raw_utterance)
    # @cleaned_utterance = ChildesAnnotation.childes_annotation2punctuation(@utterance_xml)
    # @utterance_tokens = @cleaned_utterance.split.map {|x| x.strip}

    @age =  file_info[:Years].to_f * 12.0 +  file_info[:Months].to_f
    @age_bin = @age.ceil

    @annotations = Hash.new nil
    # puts "UTTERANCE BEFORE: ", utterance
    annotations = Array.new(utterance.slice(1..-1))
    # puts "ANNOTATIONS AFTER: ", annotations
    # TODO FIXME OPTIMIZE figure out type of annotations
    # And figure out how the annotations disappear
    annotations.each do |tier|
      case tier
      when /^%mor:/ # Morphemic segments by type and PoS
        # gets rid of tab and %mor
        morph = tier.gsub(/%(.*?):\t/, "").strip

        parse = $mor_parser.parse(morph)
        if parse == nil or parse == []
          $mismatches.puts "Can't MOR parse: #{annotations}"
          puts "Can't MOR parse: #{annotations}"
          $stdout.flush
        else
          @annotations[:Morphology] = parse.struct.map {|x| x.first}
          # puts "@annotations[:Morphology]: #{@annotations[:Morphology]}"
          $stdout.flush
        end

        if @tokenized
          if @annotations[:Morphology]
            if not @tokenized.length == @annotations[:Morphology].length
              $mismatches.puts "Tokenization and morphology don't match:\n\t#{@raw_utterance}\n\t#{@tokenized.join(' ')}\n\t#{morph}"
              # puts "Tokenization and morphology don't match:\n\t#{@raw_utterance}\n\t#{@tokenized.join(' ')}\n\t#{morph}"
              # puts "Morphology length: #{@annotations[:Morphology].length}"
              @annotations[:Morphology]=nil
              # puts "Tokenization length: #{@tokenized.length}"
            else
              @tokenized.length.times do |i|
                f = get_MOR_token_form(@annotations[:Morphology][i])
                if f != @tokenized[i]
                  # This happens when stem is different from token
                  $mismatches.puts "Token and MOR don't match: #{@tokenized[i]}, #{f}"
                  # puts "Token and MOR don't match: #{@tokenized[i]}, #{f}"
                end
              end
            end
          end
        else
          $mismatches.puts "Ended up with a nil tokenization:  #{@raw_utterance}"
          puts "Ended up with a nil tokenization:  #{@raw_utterance}"
        end
      # Prefacing with x means non-standard CHAT feature
      when /^%xgra:/  # More advanced GRA feature (not sure what though)
        @annotations[:Syntax] = tier.gsub(/%(.*?):\t/, "").split.map {|x| x.strip}
      when /^%com:/  # General comment
        @annotations[:Com] = tier.gsub(/%(.*?):\t/, "")
      when /^%act:/
        @annotations[:Action] = tier.gsub(/%(.*?):\t/, "")
      when /^%int:/
        @annotations[:Intonation] = tier.gsub(/%(.*?):\t/, "")
      when /^%exp:/
        @annotations[:Exp] = tier.gsub(/%(.*?):\t/, "")
      when /^%pho:/
        @annotations[:Phonology] = tier.gsub(/%(.*?):\t/, "")
      when /^%spa:/
        @annotations[:Spa] = tier.gsub(/%(.*?):\t/, "")
      when /^%par:/
        @annotations[:Par] = tier.gsub(/%(.*?):\t/, "")
      when /^%alt:/
        @annotations[:Alt] = tier.gsub(/%(.*?):\t/, "")
      when /^%gpx:/
        @annotations[:Gpx] = tier.gsub(/%(.*?):\t/, "")
      when /^%sit:/
        @annotations[:Sit] = tier.gsub(/%(.*?):\t/, "")
      when /^%add:/
        @annotations[:Add] = tier.gsub(/%(.*?):\t/, "")
      when /^%err:/
        @annotations[:Err] = tier.gsub(/%(.*?):\t/, "")
      when /^%eng:/
        @annotations[:English] = tier.gsub(/%(.*?):\t/, "")
      when /^%trn:/
        @annotations[:Trn] = tier.gsub(/%(.*?):\t/, "")
      when /^%xgrt:/
        @annotations[:Xgrt] = tier.gsub(/%(.*?):\t/, "")
      when /^%pht:/
        @annotations[:Pht] = tier.gsub(/%(.*?):\t/, "")
      # New annotations added
      when /^%gra:/  # Standard grammatical relations tier
        @annotations[:Gra] = tier.gsub(/%(.*?):\t/, "")
      when /%xpho:/  # Non-standard phoneme tier
        @annotations[:Xpho] = tier.gsub(/%(.*?):\t/, "")
      when /^%grt:/  # Standard GRT tier
        @annotations[:grt] = tier.gsub(/%(.*?):\t/, "")
      else raise "Unknown Tier: #{tier}"
      end
    end
  end

  def to_s
    "Utterance: #{@utterance.inspect}" + "\nFile: #{@file.inspect}" + "\nMetaData: #{@metadata.inspect}" + "\nCorpus: #{@corpus.inspect}" + "\nCorpusMetaData: #{@corpus_metadata.inspect}\n"
  end

  def to_h
    # Convert to a hash for data serialization
    {
      speaker: @speaker,
      raw: @raw_utterance,
      tokenized: @tokenized,
      annotations: @annotations,
      num: @num
    }
  end
end # end childes utterance class


def parseCHILDESFile(file_info, corpusMetadata)
  # Parses a single CHILDES file specified in corpus-file-info.rb

  # Get filename from file_info hash
  puts "Parsing file #{file_info[:File]}"
  lines = File.readlines("#{CHILDES_DIRECTORY}/#{file_info[:File]}")

  # grab the file fields
  fields = []
  last_field = ""
  lines.each do |line|
    case line
    # previously @, \*, and % were all separate fields, but that seems
    # unecessary since the code is the same, so I joined them
    when /^@/, #UTF8, @PID:, @Date, @Media (basically metadata)
         /^\*/, #*CHI, *LOI, TODO find out
         /^%/# %mor, %gra, %act TODO find out
      fields = fields.push(last_field) if not last_field == ""
      last_field = line
    when /^\t/ then # Some lines are tabbed in, line continuation
      # This just makes sure line continuations are good to go
      last_field += line
    else raise "*****Don't know how to handle line! : #{line}" end
  end

  utt_num=0
  utterances = []
  metadata = []
  last_utterance = []

  fields.each do |field|
    # Get rid of line break
    field.gsub!(/[\n]/," ")
    case field
    when /^@/ then # Yep, this is metadata @PID, @Comment, etc - add to metadata file
      metadata = metadata.push(field) if not field == ""
    when /^\*/ then # These are Utterances *CHI, *PAT, etc
      if not last_utterance == []  # If we have a last utterance, this
        # Invokes the block attached to this function
        # Specifically, just count_words (446)
        utterances.push(CHILDESUtterance.new(utt_num+=1,
                                   last_utterance,
                                   file_info,
                                   metadata,
                                   corpusMetadata))
      end
      # Initialize our last utterance - so * marks beginning of utterances
      last_utterance = [field]
    when /^%/ then # Add to our last_utterance Array
      last_utterance = last_utterance.push(field)
    else raise "*****Don't know how to handle field! : #{field}" end
  end
  # This isn't actually used
  return utterances
end

def count_words(utterance)
  # puts utterance
  if utterance.tokenized
    if utterance.annotations[:Morphology]
      # I parenthesized the entire thing between not and then, not sure if correct
      # Must not be any of these speakers
      if not (/(Target_Child|Child|Playmate|Non_Human|Environment|Camera_Operator)/ =~ utterance.metadata.participants[utterance.speaker][:Role])
        if 18.0 <= utterance.age and utterance.age <= 60.0
          # For every token...
          utterance.tokenized.length.times do |index|
            word = utterance.tokenized[index]
            # Get the morphology of the word
            morphology = utterance.annotations[:Morphology][index]
            # Get morphology token of the word
            mor_cat = get_MOR_token_category(morphology)
            if /^(v|aux|part)$/ =~ mor_cat # If a verb, aux, or participle
              # Get fusional suffix from .tt grammar parse
              fusional = get_MOR_token_fusionalsuffixes(morphology)
              # same as above
              suffix = get_MOR_token_suffixes(morphology)
              # mor_subcat = get_MOR_token_subcategory(morphology)
              # puts "[fusional, suffix]"
              # puts [fusional, suffix]
              # puts "mor_cat"
              # puts mor_cat
              tag=case mor_cat
                    # FIXME: This v does not always mean verb, as evidenced
                    # by the very large amount of "Cannot find an entry for...
                    # With words like bed, interesting, box, page, etc
                  when /^v$/ then
                    case [fusional, suffix]
                    when ["","PAST"] then "VBD" # regulars
                    when ["PAST",""] then "VBD" # irregulars
                    when ["PRES",""] then "VBP" # are
                    when ["PAST",""] then "VBD" # was
                    when ["PAST|13S",""] then "VBD" # was
                    when ["","3S"] then "VBZ"
                    when ["3S",""] then "VBZ"
                    when ["ZERO",""] then "VBP" # weak verbs
                    when ["1S", ""] then "VBP" # am
                    when ["",""] then if word =="be" then "VB" else "VBP" end
                    else $stderr.puts "Don't know verb type: #{suffix} for word '#{word}' with suffix '#{suffix}' and fusional '#{fusional}'" end
                  when /^aux$/ then
                    case [fusional, suffix]
                      #when ["", "PAST"] then "VBD"
                    when ["PAST", ""] then "VBD" # did
                    when ["PRES", ""] then "VBP" # are
                    when ["COND", ""] then "VBP" # would
                    when ["", ""] then if word=="could" then "VBD"
                                       elsif word=="be" then "VB"
                                       else "VBP" end # shall, can, etc.
                    when ["3S", ""] then "VBZ"
                    when ["PAST|13S",""]  then "VBD" # was
                    when ["PERF",""]  then "VBN" # been
                    # Updated by Jesse
                    when ["PASTP", ""] then "VBN" # Updated been
                    when ["", "PRESP"] then "VBG" # -ing
                    when ["1S", ""] then "VBP" # am
                    else $stderr.puts "Don't know auxiliary type: #{suffix} for word '#{word}' with suffix '#{suffix}' and fusional '#{fusional}'" end
                  when /^part$/ then
                    case [fusional, suffix]
                    when ["", "PERF"] then "VBN"
                    when ["", "PROG"] then "VBG"
                    when ["PERF", ""] then "VBN"
                    # ING verbs seems to be Gerund
                    # Updated by Jesse
                    when ["", "PRESP"] then "VBG" # -ing
                    when ["PASTP", ""] then "VBN" # -en
                    when ["", "PASTP"] then "VBN" # -en
                    else $stderr.puts "Don't know participle type: #{suffix} for word '#{word}' with category '#{mor_cat}' and fusional '#{fusional}'" end
                  else raise "Don't know this verbal category!!" end

              if $verb_data.include?([word, tag]) then
                # puts "#{word},#{mor_cat},#{mor_subcat},#{fusional},#{suffix}"
                # Add one utterance count
                $ages[utterance.age_bin][[word, tag]] += 1
              else
                $stderr.puts "Cannot find an entry for: (#{word}, #{tag})\n\t'#{utterance.tokenized.join(' ')}' from file: '#{utterance.file_info[:File]}' \n\tmor_cat: '#{mor_cat}', fusional: '#{fusional}', suffix: '#{suffix}'"
                puts morphology
                # puts "Cannot find an entry for: (#{word}, #{tag})\n\t'#{utterance.tokenized.join(' ')}' from file: '#{utterance.file_info[:File]}' \n\tCHAT: '#{mor_cat}', '#{fusional}', '#{suffix}'"
              end
            end
          end
        end
      end
    end
  end
end

corpus_metadata={}
# For each file specified in corpus-file-info.rb
$childes_files.each do |file_info|
  # File_info is an array of hashes, each specifying one .cha file
  # We parse each file individually

  # Bloom70:Peter
  # Top becomes Bloom70
  top, _ = file_info[:Corpus].split(":")
  # There needs to be a metadata file.
  # Top is corpus folder, CHILDES_DIRECTORY specified up top
  metadata_file = "#{CHILDES_DIRECTORY}/#{top}/0metadata.cdc"

  # If the metadata, and thus corpus, hasn't been processed yet
  if not corpus_metadata.has_key?(metadata_file) then
    # Only prints if it's the first file in the corpus being parsed
    $stderr.puts "Processing Corpus: #{file_info[:Corpus]}"
    # Read the contents of the metadata file as a value for the corpus_metadata hash
    # file name is key
    corpus_metadata[metadata_file] = File.new(metadata_file, "r").readlines
  end

  $utterances = parseCHILDESFile(file_info, corpus_metadata[metadata_file])

  # utterances.each { |u| puts u.inspect }

  # This is dependent on the behavior we want
  # words_to_YAML(utterances, './CHILDES-by-ages.yaml')
end

def words_to_YAML(utterances, filename)
  $result = Hash.new do |hash, key|
    hash[key] = Hash.new nil
  end

  $ages.each_key do |age|
    $ages[age].each_pair do |verb,count|
      data = $verb_data[verb]
      $result[age][verb] = {
        :CHILDESCount => count.to_i,
        :Age => age.to_i,
        :Form => data[:Form].to_s,
        :Category => data[:Category].to_s,
        :Lemma => data[:Lemma].to_s,
        :StemTransform => data[:StemTransform].to_s,
        :Suffix => data[:Suffix].to_s,
        :CELEXFrequency => data[:CELEXFrequency].to_i,
        :PTBFrequency => data[:PTBFrequency].to_i}
    end
  end

  DataReader.save(filename, $result, :YAML, true )
end

def transcribe(utterances, filename)
  # Set up metadata
  trans = {
    metadata: utterances[0].metadata.to_a,
    utterances: utterances.collect {|u| u.to_h}
  }
  puts YAML.dump(trans)
end

transcribe($utterances, './CHILDES-by-ages.yaml')
# words_to_YAML($utterances, './CHILDES-by-ages.yaml')
