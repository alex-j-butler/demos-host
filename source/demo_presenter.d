import std.file;
import std.path;
import std.string;
import std.datetime;

//import vibe.d;
import base32;
import sizefmt;

struct DemoPresenter {
    private {
        string client;
        string user;
        DirEntry demo;
    }

    this(string client, string user, DirEntry demo) {
        this.client = client;
        this.user = user;
        this.demo = demo;
    }

    @property string downloadPath() {
        return "/static/demos/%s/%s/%s".format(client, user, name);
    }

    @property string name() {
        return demo.baseName;
    }

    @property auto size() {
        return Size(demo.size);
    }

    @property string creationTime() {
        return (cast(DateTime)demo.timeLastModified).toSimpleString;
    }

    @property string userName() {
        return cast(string)Base32.decode(user.toUpper);
    }

    @property string userPath() {
        return "/%s/%s".format(client, user);
    }
}
