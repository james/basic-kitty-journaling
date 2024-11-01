require 'json'
require 'date'
require 'io/console'
require 'ruby/openai'

data_folder = File.join(__dir__, 'data')

# Load or create data JSON
data_json_path = File.join(data_folder, 'data.json')
data_json = File.exist?(data_json_path) ? JSON.parse(File.read(data_json_path)) : {}

client = OpenAI::Client.new(access_token: data_json['openai']['apiKey'])

# Build messages array for GPT
messages = []

# Add meta prompt
messages << {
  role: 'system',
  content: "You are a chatbot named DUCKY. Your job is to help James Darling do daily journaling. " \
    "You're going to be keeping track of the questions asked and the answers given. " \
    "You are generally helpful and friendly."
}

messages << {
  role: 'system',
  content: "VERY IMPORTANT: Today is #{Time.now.strftime('%A')} and the date is #{Time.now.strftime('%d/%m/%Y')}, " \
  "the time is #{Time.now.strftime('%H:%M:%S')}. Important: Saturday and Sunday are the weekend for " \
  "relaxing not working, if the day is Saturday or Sunday make your questions less work related and more " \
  "time-off chilling related. #{data_json['name']} counts the start of the week and work week as Monday, " \
  "anything 'new week' related starts on Monday. The end of 'work week' related ends on Friday. " \
  "IMPORTANT, please don't be asking about the weekend on any other day than Monday or Friday, please pay " \
  "attention to the current day of the week."
}

messages << {
  role: 'system',
  content: "Here is a list of default questions to get you started:\n#{data_json['morningQuestions'].join("\n")}"
}

# Load previous questions and answers
qa_file = File.join(data_folder, 'previousQuestionsAndAnswers.json')
questions_and_answers = File.exist?(qa_file) ? JSON.parse(File.read(qa_file)) : {}

# Get last 5 dates with answers
last_five_dates = []
if questions_and_answers['dateMap']
  past_dates = questions_and_answers['dateMap'].reverse
  past_dates.each do |date|
    if questions_and_answers['answers'] &&
        questions_and_answers['answers'][date] &&
        !questions_and_answers['answers'][date].empty?
      last_five_dates << date
      break if last_five_dates.length == 5
    end
  end
end

# Format previous Q&As
today = Date.today.iso8601
last_five_dates.each do |date|
  next unless questions_and_answers['answers'] && questions_and_answers['answers'][date]

  days_ago = (Date.parse(today) - Date.parse(date)).to_i
  day_of_week = Date.parse(date).strftime('%A')

  qa_text = case days_ago
    when 0
      "Today, #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
    when 1
      "Yesterday, #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
    when 2
      "#{day_of_week} just gone (#{date}), #{data_json['name']}'s Q&As were:\n"
    else
      "Last #{day_of_week} (#{date}), #{data_json['name']}'s Q&As were:\n"
  end

  questions_and_answers['answers'][date].each_with_index do |qa, i|
    qa_text += "Q#{i + 1}: #{qa['question']}\n"
    qa_text += "A#{i + 1}: #{qa['answer']}\n"
  end
  qa_text += "\n"

  messages << {
    role: 'system',
    content: qa_text
  }
end

todolist = `reminders show "To do"`
  messages << {
    role: 'system',
    content: "James has a todo list, and on his todo list currently is the following:\n" + todolist
  }

# Request new questions from GPT
messages << {
  role: 'user',
  content: "Please create a set of three questions to ask in the MORNING by combining relevant questions " \
  "from the initial list and formulating new ones. When appropriate, incorporate overarching themes from " \
  "previous responses into the questions, but, very important, don\'t be overly direct with follow-up " \
  "inquiries and don\'t always reference them, you can go back to the original list of questions for guidance, " \
  "please mix it up, one question should always be new and unreliated to previous answers. " \
  "Remember the information about weekends! Put more weight on recent questions and answers rather than " \
  "older ones, questions and answers from a few days ago are less relevant than the past couple of days " \
  "(unless the last couple of days we the weekend). Put more focus on the answers given than the questions " \
  "you previously asked (they are just there for context). " \
  "Remember you are asking these at the start of the day. There must be three questions, no more or less. " \
  "Please return those three questions in .txt format with one question per line. " \
  "Important: there must be NO numbers at the start of each question! Only return the questions no other text."
}

# Print messages
puts messages.map { |m| m[:content] }.join("\n\n")

# Get questions from GPT
questions = []
escape_counter = 0

while questions.length != 3 && escape_counter < 10
  questions.clear

  if escape_counter == 0
    puts "\nThinking of some questions to ask you, please wait."
  else
    puts "Getting some different questions"
  end

  begin
    start_time = Time.now
    response = client.chat(
      parameters: {
        model: 'gpt-4o',
        messages: messages
      }
    )
    output = response.dig('choices', 0, 'message', 'content').to_s.strip.gsub(/[\r\n]+/, "\n").gsub(/[\t ]+/, ' ')

    duration = (Time.now - start_time).to_i
    puts "Response: #{duration}s"

    output.split("\n").each do |line|
      line = line.gsub(/^[0-9]+[.) :]/, '').strip
      questions << line unless line.empty?
    end
  rescue => e
    puts "Error: #{e.message}"
    exit
  end

  escape_counter += 1
end

# Add general question
questions << "Anything else you want to mention?"

# Get answers from user
answers = []
questions.each_with_index do |question, i|
  puts "\n#{i + 1}: #{question}"
  print "> "
  answer = gets.chomp
  answers << answer
end

# Save answers
date = Date.today.iso8601
questions_and_answers['answers'] ||= {}
questions_and_answers['dateMap'] ||= []
questions_and_answers['dateMap'] << date unless questions_and_answers['dateMap'].include?(date)
questions_and_answers['answers'][date] = []

questions.each_with_index do |question, i|
  next if answers[i].strip.empty?
  questions_and_answers['answers'][date] << {
    'question' => question,
    'answer' => answers[i]
  }
end

File.write(qa_file, JSON.pretty_generate(questions_and_answers))
puts "\nThank you for your time, have a good day."
