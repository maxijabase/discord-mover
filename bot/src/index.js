require('dotenv').config()

const express = require('express')
const app = express()
const bodyParser = require('body-parser')
const Discord = require('discord.js')
const client = new Discord.Client()
const CryptoJS = require("crypto-js")

const pingResponses = ['A Nisman lo mataron',
    'Hola',
    'Puto el que lee',
    'Pong!',
    '<:heysito:662081670387728424>',
    '<https://legacyhub.xyz>',
    '<:cerati:661698563931373568>',
    'Pong',
    'sale mox?',
    "Caballeros."
]


app.use(bodyParser.json())

app.listen(process.env.PORT, () => {
    console.log(`Listening on port ${process.env.PORT}`)
})

app.post('/teams', (req, res) => {
    var response = req.body
    MoveUsers(response)

    res.status(200).json({
        message: 'Post OK'
    })

})

/* Discord */

client.on('ready', () => {

    console.log(`Bot has connected as ${client.user.tag}`)
    client.user.setActivity('mox', { type: "PLAYING" })

})

client.on('message', msg => {

    if (msg.content === '!discordmover' || msg.content === '!dm') {

        var userid = encodeURIComponent(msg.author.id)
        var hash = encodeURIComponent(CryptoJS.SHA512(process.env.PRIVATEKEY + userid))

        const messageLink = new Discord.MessageEmbed()

        .setColor('#ff9001')
            .setTitle('Hacé click acá para unir tus cuentas de Discord y Steam')
            .setURL(`http://35.247.235.21/discordmover?discordid=${userid}&hash=${hash}`)
            .setDescription('No compartas este link')

        msg.author.send(messageLink).catch(() => {
            msg.channel.send('Tu configuración de privacidad me impide enviarte mensajes privados.')
        })

        return

    }

    if (msg.content === '!guia') {

        const messageGuide = new Discord.MessageEmbed()

        .setColor('#ff9001')
            .setTitle('Guía de 6v6 en Legacy Hub')
            .setURL(`https://legacyhub.xyz/es/guiamix.html`)
            .setFooter(`Solicitado por ${msg.author.tag}`)

        msg.channel.send(messageGuide)

        return

    }

    if (msg.content === '!hola') {

        msg.channel.send(pingResponses[Math.floor(Math.random() * pingResponses.length)])

    }


})

function MoveUsers(response) {

    const legacyChannels = client.guilds.cache.find(guild => guild.id == '558709360906469386').channels.cache

    var pregameChannel = legacyChannels.find(channel => channel.id == '612123722639212544')
    var REDchannel = legacyChannels.find(channel => channel.id == '558780913668849665')
    var BLUchannel = legacyChannels.find(channel => channel.id == '558780886284238848')

    if (response.instruction == 'teams') {

        var ALLmembers = REDchannel.members.array().concat(BLUchannel.members.array(), pregameChannel.members.array())

        ALLmembers.forEach(async allMember => {

            response.RED.forEach(async redMember => {

                if (redMember == allMember.id && allMember.voice.channel != REDchannel) {

                    await allMember.voice.setChannel(REDchannel)

                }

            })

            response.BLU.forEach(async bluMember => {

                if (bluMember == allMember.id && allMember.voice.channel != BLUchannel) {

                    await allMember.voice.setChannel(BLUchannel)

                }

            })

        })

        return

    }

    if (response.instruction == 'pregame') {

        var TEAMSmembers = REDchannel.members.array().concat(BLUchannel.members.array())

        TEAMSmembers.forEach(async teamMember => {

            await teamMember.voice.setChannel(pregameChannel)

        })

        return

    }

    if (response.instruction == "user") {

        var user = response.user
        var team = response.team

        var ALLmembers = REDchannel.members.array().concat(BLUchannel.members.array(), pregameChannel.members.array())

        ALLmembers.forEach(async allMember => {

            if (allMember.id == user) {

                if (team == 'red' && allMember.voice.channel != REDchannel) {

                    await allMember.voice.setChannel(REDchannel)
                    return

                }

                if (team == 'blu' && allMember.voice.channel != BLUchannel) {

                    await allMember.voice.setChannel(BLUchannel)
                    return

                }

                if (team == 'pregame' && allMember.voice.channel != pregameChannel) {

                    await allMember.voice.setChannel(pregameChannel)
                    return

                }

            }

        })

    }

}

client.login(process.env.TOKEN)