class LinebotController < ApplicationController
  require 'line/bot'
  require 'json'
  require 'oauth'

  protect_from_forgery :except => [:callback]

  API_URL = 'https://api.zaim.net/v2/'

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end

    events = client.parse_events_from(body)

    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          message = {
            type: 'text',
            text: answer_from(event.message['text'])
          }
          client.reply_message(event['replyToken'], message)
        end
      end
    end

    head :ok
  end

  private

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV['LINE_CHANNEL_SECRET']
      config.channel_token = ENV['LINE_CHANNEL_TOKEN']
    }
  end

  def total_expense(date)
    @consumer = OAuth::Consumer.new(ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET'],
                                    site: 'https://api.zaim.net',
                                    request_token_path: '/v2/auth/request',
                                    authorize_url: 'https://auth.zaim.net/users/auth',
                                    access_token_path: '/v2/auth/access')
    @access_token = OAuth::AccessToken.new(@consumer, ENV['ACCESS_TOKEN'], ENV['ACCESS_SECRET'])

    params_money = URI.encode_www_form({
      mode: 'payment',
      start_date: date,
      end_date: date,
    })

    money = @access_token.get("#{API_URL}home/money?#{params_money}")
    @money = JSON.parse(money.body)
    @amount_sum = @money['money'].inject(0) { |result, n| result + n['amount'] }
  end

  def answer_from(message)
    case message
    when '今日', 'today'
      date = Date.today.to_s
    when '昨日', 'yesterday'
      date = (Date.today - 1).to_s
    when 'おととい', '一昨日'
      dete = (Date.today - 2).to_s
    else
      return "error"
    end

    answer = "#{date}の支出は#{total_expense(date)}円です"
  end
end
