Viết 1 service OpenAI cung cấp api để sử dụng được lib OpenAI 
mở service người dùng truy cập thông qua
baseURL: config.baseUrl,
apiKey: config.apiKey,

baseUrl sẽ mở ở port 3003
apiKey (get/post/delete) được gen từ secret-key (từ .env) và lưu ở file local key.json và được mã hoá kết hợp với salt-key từ .env

Thư viện hỗ trợ:
https://www.npmjs.com/package/@mariozechner/pi-ai


Người dùng -> Kết nối service -> Kiểm tra key -> Kết nối pi-ai -> Kết nối Claude code -> Result 
(Key Oauth Claude code setup ở .env )