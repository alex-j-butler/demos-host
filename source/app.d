import std.file;
import std.path;
import std.array;
import std.ascii;
import std.algorithm;

import base32;
import vibe.d;
import vibe.web.web;

static import config.application;

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

    listenHTTP(settings, router);
    logInfo("See status at http://127.0.0.1:%s/status".format(settings.port));
}

static auto router() {
    auto router = new URLRouter;

    router.registerWebInterface(new DemosHost);

    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("/status", &getStatus);
    router.get("*", serveStaticFiles("public/", fsettings));

    return router;
}

void getStatus(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    res.writeBody("Running");
}

class DemosHost {
    const DEMOS_PATH = buildPath("public", "demos");

    @path("/:client/:user")
    void getUser(string _client, string _user, scope HTTPServerResponse res) {
        // Sanitize Client
        auto clients = dirEntries(DEMOS_PATH, SpanMode.shallow).map!(d => d.baseName);
        enforceHTTP(clients.canFind(_client), HTTPStatus.notFound, "Client not found");

        // Sanitize User
        auto users = dirEntries(buildPath(DEMOS_PATH, _client), SpanMode.shallow).map!(d => d.baseName);
        enforceHTTP(users.canFind(_user), HTTPStatus.notFound, "User not found");

        auto userPath = buildPath(DEMOS_PATH, _client, _user);
        auto userName = cast(string)Base32.decode(_user.toUpper);
        auto demoFiles = dirEntries(userPath, "*.dem", SpanMode.shallow).array;
        auto demos = demoFiles.sort!"a.timeLastModified < b.timeLastModified";

        res.render!("demos.dt", _client, _user, userPath, userName, demos);
    }
}
