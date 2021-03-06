import std.utf;
import std.conv;
import std.file;
import std.path;
import std.array;
import std.ascii;
import std.range;
import std.typecons;
import std.algorithm;

import base32;
import vibe.d;
import vibe.web.web;

static import config.application;

const DEMOS_PATH = buildPath("public", "demos");
const MAX_DISTANCE = 0.3;

version (unittest) {} else
shared static this() {
    auto settings = config.application.serverSettings;

    // Log access to the log file
    //settings.accessLogToConsole = true;
    settings.accessLogFile = config.application.logFile;

    // Log to the proper log file
    auto fileLogger = cast(shared)new FileLogger(config.application.logFile);
    fileLogger.minLevel = config.application.logLevel;
    registerLogger(fileLogger);

    // Better log formatting
    setLogFormat(FileLogger.Format.thread, FileLogger.Format.thread);

    // Error page
    settings.errorPageHandler = (res, req, err) => errorPage(res, req, err);

    listenHTTP(settings, router);
}

void errorPage(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo err) {
    // Log all exceptions
    logError("%s", err.exception);
    // Don't fill the log with status exceptions, those we can usually ignore
    if (cast(HTTPStatusException)err.exception) logInfo("%s", err.exception.info);

    res.render!("error.dt", err);
}

auto getClients() {
    return dirEntries(DEMOS_PATH, SpanMode.shallow).map!(d => d.baseName);
}

auto getUsers() {
    auto clients = getClients();
    return clients.map!(client => getUsers(client).map!(user => tuple(client, user))).joiner;
}

auto getUsers(string client) {
    return dirEntries(buildPath(DEMOS_PATH, client), SpanMode.shallow).map!(d => d.baseName);
}

auto getDemos(string client, string user) {
    return dirEntries(buildPath(DEMOS_PATH, client, user), "*.dem", SpanMode.shallow).map!(d => d);
}

auto getDemos() {
    auto users = getUsers();
    return users.map!((t) => getDemos(t[0], t[1]).map!(demo => tuple(t[0], t[1], demo))).joiner;
}

float normalizedLevenshteinDistance(string query, string name) {
    float distance = levenshteinDistance(query, name);

    // Normalize by length
    float maxLength = max(query.length, name.length);
    return max(0.0, 1.0 - distance / maxLength);
}

auto findUsers(string query) {
    query = query.toUpper;
    auto users = getUsers();
    Tuple!(string, string, string, float)[] goodMatches;

    foreach (group; users) {
        string userName;
        try {
            userName = cast(string)Base32.decode(group[1].toUpper);
        } catch(Base32Exception e) {
            continue;
        }
        auto name = userName.toUpper;

        auto distance = normalizedLevenshteinDistance(query, name);

        // Check for Discord user names
        if (userName.length > 5 && userName[$-5] == '#') {
            auto discordName = name[0..$-5];
            distance = max(distance, normalizedLevenshteinDistance(query, discordName));
        }

        // Collect good matches
        if (distance >= MAX_DISTANCE) {
            goodMatches ~= tuple(group[0], group[1], userName, distance);
        }
    }

    return goodMatches;
}

auto router() {
    auto router = new URLRouter;

    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "";
    router.get("*", serveStaticFiles("public/", fsettings));

    router.registerWebInterface(new DemosHost);

    return router;
}

class DemosHost {
    @path("/api/users")
    void getUsersAPI(scope HTTPServerResponse res) {
        struct User {
            string client;
            string enc_name;
            string name;
        }

        auto usrs = getUsers().map!(users => User(users[0], users[1], cast(string)Base32.decode(users[1].toUpper))).array;
        res.writeJsonBody(usrs);
    }

    @path("/api/demos/:client/:encuser")
    void getDemosAPI(string _client, string _encuser, scope HTTPServerResponse res) {
        struct Demo {
            string client;
            string name;
            string demo_name;
            string download_path;
            ulong size;
            DateTime creation_time;
        }
        
        auto demoFiles = getDemos(_client, _encuser).array;
        auto demos = demoFiles.sort!"a.timeLastModified > b.timeLastModified";
        auto userDemos = demos.map!(demo => Demo(_client, _encuser, demo.baseName, "/demos/%s/%s/%s".format(_client, _encuser, demo.baseName), demo.size, cast(DateTime)demo.timeLastModified)).array;
        res.writeJsonBody(userDemos);
    }

    @path("/")
    void getIndex(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        Tuple!(string, string, string, float)[] users;
        Tuple!(string, string, DirEntry)[] demos;

        // Get search query
        string query;
        if ("q" in req.query) query = req.query["q"];
        if (query.length == 0) query = null;

        // Get user or demo data
        if (query !is null) {
            users = findUsers(query).sort!"a[3] > b[3]".array;
        } else {
            auto allDemos = getDemos().array;
            // Get top 10 demos by time
            demos = new Tuple!(string, string, DirEntry)[10];
            demos = allDemos.topNCopy!"a[2].timeLastModified > b[2].timeLastModified"(demos, Yes.sortOutput);
        }

        res.render!("index.dt", query, demos, users);
    }

    @path("/:client/:user")
    void getUser(string _client, string _user, scope HTTPServerResponse res) {
        // Sanitize Client
        auto clients = getClients();
        enforceHTTP(clients.canFind(_client), HTTPStatus.notFound, "Client not found");
        auto client = _client;

        // Sanitize User
        auto users = getUsers(_client);
        if (!users.canFind(_user)) {
            // Show an empty page for valid users that don't have demos
            string userName;
            try {
                userName = cast(string)Base32.decode(_user.toUpper);
                // Filter out invalid UTF-8 characters
                userName = userName.to!dstring.filter!isValidDchar.array.to!string;
            } catch (Exception e) {
                if (cast(Base32Exception)e || cast(UTFException)e) {
                    throw new HTTPStatusException(HTTPStatus.badRequest, "Invalid User");
                }
                throw e;
            }
            res.render!("demos_empty.dt", client, userName);
            return;
        }
        auto user = _user;

        auto userPath = buildPath(DEMOS_PATH, _client, _user);
        auto userName = cast(string)Base32.decode(_user.toUpper);
        auto demoFiles = getDemos(_client, _user).array;
        auto demos = demoFiles.sort!"a.timeLastModified > b.timeLastModified";

        res.render!("demos.dt", client, user, userPath, userName, demos);
    }
}
