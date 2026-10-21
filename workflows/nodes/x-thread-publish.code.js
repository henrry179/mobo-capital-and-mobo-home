// n8n Code 节点：自动链式发布 X Thread (严守 350MB 内存红线，零第三方重型 SDK)
const threadArray = $input.first().json.x_thread_json;
let previousTweetId = null;
const publishedTweetIds = [];

for (let i = 0; i < threadArray.length; i++) {
  const payload = { text: threadArray[i] };
  
  if (previousTweetId) {
    payload.reply = { in_reply_to_tweet_id: previousTweetId };
  }

  const response = await this.helpers.httpRequestWithAuthentication.call(
    this,
    'twitterOAuth2Api',
    {
      method: 'POST',
      url: 'https://api.twitter.com/2/tweets',
      body: payload,
      json: true,
    }
  );

  previousTweetId = response.data.id;
  publishedTweetIds.push(previousTweetId);
  await new Promise(resolve => setTimeout(resolve, 1500));
}

return [{
  json: {
    x_root_tweet_id: publishedTweetIds[0],
    x_thread_count: publishedTweetIds.length,
    x_thread_url: `https://x.com/i/web/status/${publishedTweetIds[0]}`
  }
}];