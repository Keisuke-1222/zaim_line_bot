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

  def answer_from(message)
    if message.include?('平均')
      period = message.delete('^0-9').to_i
      @start_date = (Date.today - period + 1).to_s
      @end_date = Date.today.to_s

      answer = "#{period}日間の平均支出は#{total_expense / period}円です"
    elsif message.include?('追加')
      @add_amount = message.delete('^0-9').to_i
      payment = @access_token.post("#{API_URL}home/money/payment?#{payment_params}")

      answer = "#{@add_amount}円を家計簿に追加しました"
    else
      if message.include?('今日')
        @start_date = @end_date = Date.today.to_s
      elsif message.include?('昨日')
        @start_date = @end_date = (Date.today - 1).to_s
      elsif message.include?('一昨日')
        @start_date = @end_date = (Date.today - 2).to_s
      else
        return 'error'
      end

      answer = "#{@start_date}の支出は#{total_expense}円です"
    end
  end

  def total_expense
    set_zaim_consumer_and_access_token

    money = JSON.parse(@access_token.get("#{API_URL}home/money?#{money_params}").body)
    money['money'].inject(0) { |result, n| result + n['amount'] }
  end

  def money_params
    URI.encode_www_form({
      mode: 'payment',
      start_date: @start_date,
      end_date: @end_date,
    })
  end

  def payment_params
    URI.encode_www_form({
      mapping: 1,
      category_id: 101,
      genre_id: 10101,
      amount: @add_amount,
      date: Date.today.to_s
    })
  end

  def set_zaim_consumer_and_access_token
    @consumer = OAuth::Consumer.new(ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET'],
                                    site: 'https://api.zaim.net',
                                    request_token_path: '/v2/auth/request',
                                    authorize_url: 'https://auth.zaim.net/users/auth',
                                    access_token_path: '/v2/auth/access')
    @access_token = OAuth::AccessToken.new(@consumer, ENV['ACCESS_TOKEN'], ENV['ACCESS_SECRET'])
  end
end
