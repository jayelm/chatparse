require 'find'
require 'sqlite3'
require 'corpus-file-info'
require 'set'
require 'treetop'
require 'mor'
require 'chat'
require 'data_reader'

CHILDES_DIRECTORY = "/Users/timo/Data/Childes/Corpora/"
$verb_data = DataReader.hashonkeys_load('/Users/timo/Projects/fragment-grammar/Simulations/PastTense/Data/verbs-CHILDES-SWBD.csv',[:Form,:Category], :CSV)

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
      else raise "Unknown metadata field: #{field}" end
    end
  end
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
  def initialize(num, utterance, file_info, metadata, corpusMetadata)
    @tokenized = nil
    @num = num
    @file_info = file_info
    @metadata = CHILDESUtteranceMetadata.new(Array.new(metadata))
    @corpus_metadata = Array.new(corpusMetadata)

    tokens = utterance.first.split.map { |t| t.strip }    
    @speaker= tokens[0].gsub(/[*:]/,"").strip
    @raw_utterance = tokens.slice(1,:end).join(" ").gsub(/[^ ],/, " ,") #we have to make a number of fixes to the raw data to get parsing to work

    # $mismatches.puts "Parsing: #{@raw_utterance}"
    p=$chat_parser.parse(@raw_utterance)
    if p == nil
      $mismatches.puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
      $stdout.flush
    else
      # $mismatches.puts "Parsed:\n\t#{@raw_utterance}\n\t#{to_tree(p)}\n\t#{p.replace}"
      $stdout.flush
      @tokenized = p.replace.gsub(/ ta /," to ").gsub(/mhm/, "yes").split.map {|t| t.strip}
    end

    # @utterance_xml = ChildesAnnotation.convert_CHAT2xml( @raw_utterance)
    # @cleaned_utterance = ChildesAnnotation.childes_annotation2punctuation(@utterance_xml) 
    # @utterance_tokens = @cleaned_utterance.split.map {|x| x.strip}

    @age =  file_info[:Years].to_f * 12.0 +  file_info[:Months].to_f
    @age_bin = @age.ceil
    
    @annotations = Hash.new nil
    annotations = Array.new(utterance.slice(1,:end))
    annotations.each do |tier|
      case tier
      when /^%mor:/ then 
        morph=tier.gsub(/%(.*?):\t/, "").strip

        parse=$mor_parser.parse(morph)
        if parse == nil or parse == []
        then 
          $mismatches.puts "Can't MOR parse: #{annotations}"
          $stdout.flush
        else
          @annotations[:Morphology]=parse.struct.map {|x| x.first}
          $stdout.flush
        end

        
        if @tokenized then
          if @annotations[:Morphology]
            if (not @tokenized.length == @annotations[:Morphology].length) 
            then 
              $mismatches.puts "Tokenization and morphology don't match:\n\t#{@raw_utterance}\n\t#{@tokenized.join(' ')}\n\t#{morph}" 
              @annotations[:Morphology]=nil
            else
              @tokenized.length.times do |i| 
                f=get_MOR_token_form(@annotations[:Morphology][i])
                if f != @tokenized[i] then
                  $mismatches.puts "Token and MOR don't match: #{@tokenized[i]}, #{f}"
                end
              end
            end
          end
        else
          $mismatches.puts "Ended up with a nil tokenization:  #{@raw_utterance}"
        end
          

      when /^%xgra:/ then 
        @annotations[:Syntax] = tier.gsub(/%(.*?):\t/, "").split.map {|x| x.strip}
      when /^%com:/ then 
        @annotations[:Com] = tier.gsub(/%(.*?):\t/, "")
      when /^%act:/ then 
        @annotations[:Action] = tier.gsub(/%(.*?):\t/, "")
      when /^%int:/ then 
        @annotations[:Intonation] = tier.gsub(/%(.*?):\t/, "")
      when /^%exp:/ then 
        @annotations[:Exp] = tier.gsub(/%(.*?):\t/, "")
      when /^%pho:/ then 
        @annotations[:Phonology] = tier.gsub(/%(.*?):\t/, "")
      when /^%spa:/ then 
        @annotations[:Spa] = tier.gsub(/%(.*?):\t/, "")
      when /^%par:/ then 
        @annotations[:Par] = tier.gsub(/%(.*?):\t/, "")
      when /^%alt:/ then 
        @annotations[:Alt] = tier.gsub(/%(.*?):\t/, "")
      when /^%gpx:/ then 
        @annotations[:Gpx] = tier.gsub(/%(.*?):\t/, "")
      when /^%sit:/ then 
        @annotations[:Sit] = tier.gsub(/%(.*?):\t/, "")
      when /^%add:/ then 
        @annotations[:Add] = tier.gsub(/%(.*?):\t/, "")
      when /^%err:/ then 
        @annotations[:Err] = tier.gsub(/%(.*?):\t/, "")
      when /^%eng:/ then 
        @annotations[:English] = tier.gsub(/%(.*?):\t/, "")
      when /^%trn:/ then 
        @annotations[:Trn] = tier.gsub(/%(.*?):\t/, "")
      when /^%xgrt:/ then 
        @annotations[:Xgrt] = tier.gsub(/%(.*?):\t/, "")
      when /^%pht:/ then 
        @annotations[:Pht] = tier.gsub(/%(.*?):\t/, "")
      else raise "Unknown Tier: #{tier}"end	
    end
  end

  def to_s
    "Utterance: #{@utterance.inspect}" + "\nFile: #{@file.inspect}" + "\nMetaData: #{@metadata.inspect}" + "\nCorpus: #{@corpus.inspect}" + "\nCorpusMetaData: #{@corpusMetadata.inspect}\n"
  end  
end # end childes utterance class


def parseCHILDESFile (file_info, corpusMetadata )
  lines = File.readlines("#{CHILDES_DIRECTORY}/#{file_info[:File]}")

  #grab the file fields
  fields = []
  last_field = ""
  lines.each do |line|
    case line
    when /^@/ then 
      fields = fields.push(last_field) if not last_field == ""
      last_field = line
    when /^\*/ then  
      fields = fields.push(last_field) if not last_field == ""
      last_field = line
    when /^%/ then   
      fields = fields.push(last_field) if not last_field == ""
      last_field = line
    when /^\t/ then 
      last_field += line
    else raise "*****Don't know how to handle line! : #{line}" end
  end

  utt_num=0
  utterances = []
  metadata = []
  last_utterance = []
  fields.each do |field|
    field.gsub!(/[\n]/," ")

    case field
    when /^@/ then 
      metadata = metadata.push(field) if not field == ""
    when /^\*/ then  
      yield CHILDESUtterance.new(utt_num+=1,last_utterance,file_info,metadata,corpusMetadata) if not last_utterance == []
       #utterances = utterances.push() 
      last_utterance = [field]
    when /^%/ then   
      last_utterance = last_utterance.push(field)
    else raise "*****Don't know how to handle field! : #{field}" end

  end
  return utterances
end

def count_words( utterance )
  if utterance.tokenized 
    if utterance.annotations[:Morphology] 
      if not /(Target_Child|Child|Playmate|Non_Human|Environment|Camera_Operator)/ =~ utterance.metadata.participants[utterance.speaker][:Role] then
        if 18.0 <= utterance.age and utterance.age <= 60.0
          utterance.tokenized.length.times do |index|
            word = utterance.tokenized[index]           
            morphology=utterance.annotations[:Morphology][index]
            mor_cat = get_MOR_token_category(morphology)
            if /^(v|aux|part)$/ =~ mor_cat
              fusional = get_MOR_token_fusionalsuffixes(morphology)
              suffix = get_MOR_token_suffixes(morphology)
              mor_subcat = get_MOR_token_subcategory(morphology)
              tag=case mor_cat 
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
                    when ["1S", ""] then "VBP" # am
                    else $stderr.puts "Don't know auxiliary type: #{suffix} for word '#{word}' with suffix '#{suffix}' and fusional '#{fusional}'" end
                  when /^part$/ then
                    case [fusional, suffix]
                    when ["", "PERF"] then "VBN"
                    when ["", "PROG"] then "VBG"
                    when ["PERF", ""] then "VBN"
                    else $stderr.puts "Don't know participle type: #{suffix} for word '#{word}' with category '#{mor_cat}' and fusional '#{fusional}'" end
                  else raise "Don't know this verbal category!!" end
              
              if $verb_data.include?([word,tag]) then
                # puts "#{word},#{mor_cat},#{mor_subcat},#{fusional},#{suffix}"
                $ages[utterance.age_bin][[word, tag]] += 1
              else
                #puts "Cannot find an entry for: (#{word}, #{tag})\n\t'#{utterance.tokenized.join(' ')}' from file: '#{utterance.file_info[:File]}' \n\tCHAT: '#{mor_cat}', '#{fusional}', '#{suffix}'"
              end
            end
          end
        end
      end
    end
  end
end

corpus_metadata={}
$childes_files.each do |file_info|
  top,bottom = file_info[:Corpus].split(":")
  metadata_file = "#{CHILDES_DIRECTORY}/#{top}/0metadata.cdc"

  if not corpus_metadata.has_key?(metadata_file) then
    $stderr.puts "Processing Corpus: #{file_info[:Corpus]}"
    corpus_metadata[metadata_file] = File.new(metadata_file, "r").readlines 
  end

  parseCHILDESFile(file_info, corpus_metadata[metadata_file]) do  |utterance|
        count_words utterance
  end
end

$result = Hash.new do |hash,key| hash[key] = Hash.new nil end

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

DataReader.save('/Users/timo/Projects/fragment-grammar/Simulations/PastTense/Data/CHILDES-by-ages.yaml', $result, :YAML, true )
