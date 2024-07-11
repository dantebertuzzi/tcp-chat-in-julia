using Sockets
using Dates

const SERVER_IP_ADDRESS = Sockets.localhost
const SERVER_PORT_NUMBER = 50000
const COLORS = ["\e[31m", "\e[32m", "\e[33m", "\e[34m", "\e[35m", "\e[36m"]
const RESET_COLOR = "\e[0m"

function try_send(socket, message)
    try
        println(socket, message)
    catch error
        @error error
        close(socket)
    end
    return nothing
end

function try_broadcast(room, message)
    for socket in room
        try_send(socket, message)
    end
    return nothing
end

is_valid_nickname(nickname) = occursin(r"^[A-Za-z0-9]{1,32}$", nickname)

is_valid_message(message) = !isempty(message) && all(char -> isprint(char) && isascii(char), message)

function handle_socket(room, room_lock, socket, users, color_map)
    peername = Sockets.getpeername(socket)
    client_ip_address = peername[1]
    client_port_number = Int(peername[2])
    @info "Socket accepted" client_ip_address client_port_number

    try_send(socket, "Digite um nickname")
    nickname = readline(socket)
    @info "Nickname escolhido" client_ip_address client_port_number nickname

    if is_valid_nickname(nickname) && !haskey(users, nickname)
        user_entry_message = "[$(nickname) entrou na sala]"
        color = COLORS[mod(length(users), length(COLORS)) + 1]

        lock(room_lock) do
            push!(room, socket)
            users[nickname] = socket
            color_map[socket] = color
            @info "Broadcasting user entry message" client_ip_address client_port_number nickname message=user_entry_message
            try_broadcast(room, user_entry_message)
        end

        while !eof(socket)
            chat_message = readline(socket)
            if is_valid_message(chat_message)
                if startswith(chat_message, "/")
                    process_command(chat_message, socket, nickname, users, room, room_lock)
                else
                    timestamp = Dates.format(now(), "yyyy-mm-dd/HH:MM:SS")
                    color = color_map[socket]
                    chat_message_with_nickname = "$(color)[$(timestamp)] └ @$(nickname)>>> $(chat_message)$(RESET_COLOR)"
                    lock(room_lock) do
                        @info "Broadcasting chat message" client_ip_address client_port_number nickname message=chat_message_with_nickname
                        try_broadcast(room, chat_message_with_nickname)
                    end
                end
            else
                @info "Invalid chat message" client_ip_address client_port_number nickname message=chat_message
                try_send(socket, "[ERROR: message must be composed only of printable ascii characters]")
                close(socket)
                break
            end
        end

        user_exit_message = "[$(nickname) saiu da sala]"
        lock(room_lock) do
            pop!(room, socket)
            delete!(users, nickname)
            delete!(color_map, socket)
            @info "Broadcasting user exit message" client_ip_address client_port_number nickname message=user_exit_message
            try_broadcast(room, user_exit_message)
        end
    else
        @info "Invalid nickname" client_ip_address client_port_number nickname
        try_send(socket, "[ERROR: nickname must be composed only of a-z, A-Z, and 0-9 and its length must be between 1 to 32 characters (both inclusive)]")
        close(socket)
    end

    @info "Socket closed" client_ip_address client_port_number nickname

    return nothing
end

function process_command(command, socket, nickname, users, room, room_lock)
    parts = split(command, ' ', limit=2)
    cmd = parts[1]
    args = length(parts) > 1 ? parts[2] : ""

    if cmd == "/pm"
        pm_parts = split(args, ' ', limit=2)
        if length(pm_parts) < 2
            try_send(socket, "[ERROR: usage /pm <nickname> <message>]")
            return
        end
        target_nickname = pm_parts[1]
        message = pm_parts[2]

        if haskey(users, target_nickname)
            target_socket = users[target_nickname]
            try_send(target_socket, "[PM from $(nickname)]: $(message)")
        else
            try_send(socket, "[ERROR: user $(target_nickname) not found]")
        end
    elseif cmd == "/list"
        user_list = join(keys(users), ", ")
        try_send(socket, "[Active users: $(user_list)]")
    else
        try_send(socket, "[ERROR: unknown command $(cmd)]")
    end

    return nothing
end

function start_server(server_ip_address, server_port_number)
    room = Set{Sockets.TCPSocket}()
    room_lock = ReentrantLock()
    users = Dict{String, Sockets.TCPSocket}()
    color_map = Dict{Sockets.TCPSocket, String}()

    server = Sockets.listen(server_ip_address, server_port_number)
    @info "Server started listening" server_ip_address server_port_number

    while true
        socket = Sockets.accept(server)
        errormonitor(@async handle_socket(room, room_lock, socket, users, color_map))
    end

    return nothing
end

start_server(SERVER_IP_ADDRESS, SERVER_PORT_NUMBER)
