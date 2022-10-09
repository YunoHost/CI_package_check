#! /usr/bin/python3
# coding: utf-8

import sys
import os
import xmpp
from contextlib import contextmanager


@contextmanager
def XMPPBot(password, room="dev"):
    jid = xmpp.protocol.JID("gitbot@im.yunohost.org")

    client = xmpp.Client(jid.getDomain(), debug=[])

    # hack to connect only if I need to send messages
    client.connected = False

    def connect():
        client.connect()

        # yes, this is how this stupid lib tells you that the connection
        # succeed, it return the string "sasl", this doesn't make any sens and
        # it documented nowhere, because xmpp is THE FUTUR
        if client.auth(jid.getNode(), password) != "sasl":
            print("Failed to connect, bad login/password combination")
            sys.exit(1)

        client.sendInitPresence(requestRoster=0)

        presence = xmpp.Presence(to="%s@conference.yunohost.org" % room)
        presence.setTag('x', namespace='http://jabber.org/protocol/muc')

        client.send(presence)

        client.send(xmpp.Presence(to='%s@conference.yunohost.org/AppCI' % room))

    def sendToChatRoom(message):
        if not client.connected:
            connect()
            client.connected = True

        client.send(xmpp.protocol.Message("%s@conference.yunohost.org" % room, message, typ="groupchat"))

    client.sendToChatRoom = sendToChatRoom

    yield client

    if client.connected:
        client.disconnect()


if __name__ == '__main__':
    if len(sys.argv[1:]) < 1:
        print("Usage : ./xmpp_notify.py <message>")
        sys.exit(1)

    message = sys.argv[1]
    password = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"../.xmpp_password")).read().strip()
    room = "apps"

    with XMPPBot(password, room=room) as bot:
        bot.sendToChatRoom(message)
