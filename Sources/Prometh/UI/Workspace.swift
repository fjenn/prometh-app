import SwiftUI
import AppKit

struct WorkspaceView: View {
    @ObservedObject var store:PromethStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var sidebar=true;@State var renaming:UUID?;@State var renameText="";@State var deleting:UUID?
    @State var editing:Message?;@State var editText="";@State var sourcePreview=false
    var isEvil:Bool {store.displayedMode == .evil}
    var body:some View {
        HStack(spacing:0){if sidebar{sidebarView.frame(width:240);Divider()};main}
            .background(scheme == .dark ? Color(hex:0x20232B):Color(hex:0xFAF9F6))
            .sheet(isPresented:Binding(get:{renaming != nil},set:{if !$0{renaming=nil}})){VStack(alignment:.leading,spacing:20){Text("Name this conversation").font(.title2);TextField("Conversation title",text:$renameText).textFieldStyle(.roundedBorder).onSubmit{commitRename()};HStack{Button("Cancel"){renaming=nil}.keyboardShortcut(.cancelAction);Spacer();Button("Save"){commitRename()}.keyboardShortcut(.defaultAction)}}.padding(28).frame(width:420)}
            .sheet(item:$editing){m in VStack(alignment:.leading,spacing:16){Text("Edit your message").font(.title2);Text("Saving replaces the replies that follow this message.").foregroundStyle(.secondary);TextEditor(text:$editText).font(.body).frame(height:130).padding(8).background(.quaternary,in:RoundedRectangle(cornerRadius:12));HStack{Button("Cancel"){editing=nil};Spacer();Button("Save & send"){store.editMessage(m,text:editText);editing=nil}.buttonStyle(PrimaryButton()).disabled(editText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:520)}
            .confirmationDialog("Delete this conversation?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Delete conversation",role:.destructive){if let id=deleting{store.delete(id)};deleting=nil};Button("Cancel",role:.cancel){deleting=nil}}message:{Text("This removes it from your history.")}
            .sheet(isPresented:$sourcePreview){VStack(alignment:.leading,spacing:20){Text("Connected apps").font(.title2);ConnectorsList(store:store);Button("Done"){sourcePreview=false}}.padding(32).frame(width:460)}
            .sheet(item:Binding(get:{store.pendingConnectorApproval},set:{if $0 == nil {store.connectorSheetDismissed()}})){_ in VStack(alignment:.leading,spacing:20){Text("Approve connected-app action").font(.title2);Text("This action is sent only after you approve it.").foregroundStyle(.secondary);HStack{Button("Deny"){store.denyConnector()}.keyboardShortcut(.cancelAction);Spacer();Button("Approve"){store.approveConnector()}.keyboardShortcut(.defaultAction).buttonStyle(PrimaryButton())}}.padding(28).frame(width:460).accessibilityIdentifier("prometh.connector.approval")}
    }
    func commitRename(){if let id=renaming{store.rename(id,renameText)};renaming=nil}
    var sidebarView:some View {
        VStack(alignment:.leading,spacing:20){Brand().padding(.top,20)
            Button{store.newChat()}label:{HStack{Image(systemName:"square.and.pencil");Text("New chat");Spacer();Text("⌘N").font(.caption).foregroundStyle(.secondary)}.padding(12).background(.background.opacity(0.7),in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).accessibilityIdentifier("prometh.sidebar")
            HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search conversations",text:$store.search).textFieldStyle(.plain).font(.system(size:12)).accessibilityIdentifier("prometh.search")}.padding(10).background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
            Text(store.search.isEmpty ? "YOUR CONVERSATIONS":"SEARCH RESULTS").font(.system(size:9,weight:.semibold)).tracking(1.4).foregroundStyle(.secondary)
            ScrollView{VStack(spacing:5){ForEach(store.filteredChats){c in HStack(spacing:3){Button{store.select(c.id)}label:{HStack(spacing:9){Image(systemName:c.messages.contains{$0.artifact != nil} ? "photo":"bubble.left").font(.system(size:12)).foregroundStyle(.secondary);Text(c.title).font(.system(size:12,weight:c.id==store.state.selectedChatID ? .medium:.regular)).lineLimit(1);Spacer(minLength:0)}.padding(.vertical,12).padding(.leading,10).contentShape(Rectangle())}.buttonStyle(.plain);Menu{Button("Rename"){renameText=c.title;renaming=c.id};Button("Export"){store.select(c.id);store.exportChat()};Button("Delete",role:.destructive){deleting=c.id}}label:{Image(systemName:"ellipsis").frame(width:22,height:26).accessibilityLabel("Conversation actions").accessibilityIdentifier("prometh.conversation.actions")}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.trailing,5).help("Conversation actions").accessibilityLabel("Conversation actions").accessibilityIdentifier("prometh.conversation.actions")}.background(c.id==store.state.selectedChatID ? Color.primary.opacity(scheme == .dark ? 0.08:0.05):.clear,in:RoundedRectangle(cornerRadius:12))};if store.filteredChats.isEmpty{Text("No conversations found").font(.caption).foregroundStyle(.secondary).padding()}}}.scrollIndicators(.hidden)
            Spacer(minLength:0)
            if store.state.selected.contains(where:{store.state.preparations[$0.rawValue]?.status != .ready}){Button{store.settingsTab="Capabilities";store.settingsOpen=true}label:{HStack{Image(systemName:"circle.dotted");Text("Your AI is getting ready").font(.system(size:11));Spacer();Image(systemName:"chevron.right").font(.caption)}}.buttonStyle(.plain).padding(12).background(Color.butter.opacity(0.18),in:RoundedRectangle(cornerRadius:12))}
            Button{store.openCustomize()}label:{HStack{Image(systemName:"slider.horizontal.3");Text("Customize");Spacer();Text("⇧⌘C").font(.caption).foregroundStyle(.secondary)}.padding(12).background(.background.opacity(0.7),in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).font(.system(size:13)).help("Plugins, tools and skills")
            HStack{Button{store.settingsOpen=true}label:{Label("Settings",systemImage:"gearshape").font(.system(size:13))}.buttonStyle(.plain);Spacer();Image(systemName:"lock.fill").font(.system(size:10)).foregroundStyle(.secondary)}
            Text("Private · On this Mac").font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(18).background{if scheme == .dark {LinearGradient(colors:[Color(hex:0x29313C),Color(hex:0x302D3B),Color(hex:0x2B2E32)],startPoint:.topLeading,endPoint:.bottomTrailing)} else {Color(hex:0xF4F3F1)}}.accessibilityElement(children:.contain).accessibilityIdentifier("prometh.sidebar")
    }
    var centered:Bool {(store.current?.messages.isEmpty ?? true) && !store.voice.isOpen}
    var draftEmpty:Bool {(store.current?.draft ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && (store.current?.attachments.isEmpty ?? true)}
    var running:Bool {store.current.map{store.isRunning($0.id)} == true}
    var main:some View {
        VStack(spacing:0) {
            header
            Rectangle().fill(isEvil ? Color(hex:0xE06B62).opacity(0.9):Color.primary.opacity(0.08)).frame(height:isEvil ? 2:1)
            if centered {
                Spacer(minLength:0)
                composer
                Spacer(minLength:0)
            } else {
                if let c=store.current,!c.messages.isEmpty {transcript(c)} else {Spacer(minLength:0)}
                if store.voice.isOpen {voiceLayer.padding(.top,12).padding(.bottom,10)}
                composer.padding(.bottom,16)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    var header:some View {
        HStack(spacing:14) {
            IconButton(symbol:"sidebar.left",title:"Toggle sidebar"){sidebar.toggle()}
            VStack(alignment:.leading,spacing:2) {
                Text(store.current?.title ?? "New chat").font(.system(size:13,weight:.medium)).lineLimit(1)
                Text(isEvil ? "Evil Mode":"Safe Mode").font(.system(size:11)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu{Button("Rename conversation"){if let c=store.current{renaming=c.id;renameText=c.title}};Button("Export conversation"){store.exportChat()}}label:{Image(systemName:"ellipsis").frame(width:25,height:28).accessibilityLabel("Conversation menu").accessibilityIdentifier("prometh.conversation.menu")}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Conversation menu").accessibilityIdentifier("prometh.conversation.menu")
        }.padding(.horizontal,22).padding(.vertical,14)
    }
    var voiceLayer:some View {
        VStack(spacing:10) {
            Button{store.voice.sampleTurn()}label:{FluidOrb(speaking:store.voice.phase=="Speaking")}.buttonStyle(.plain).accessibilityLabel("Record or finish speaking")
            Text(store.voice.phase).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(3)
            if !store.voice.recovery.isEmpty {Text(store.voice.recovery).font(.system(size:11)).foregroundStyle(.secondary)}
            if !store.voice.transcript.isEmpty {ScrollView{Text(store.voice.transcript).font(.system(size:13)).textSelection(.enabled)}.frame(maxHeight:100)}
            HStack{Button(store.voice.muted ? "Unmute":"Mute"){store.voice.toggleMute()};Button("Interrupt"){store.voice.interrupt()};Button("End voice"){store.voice.end()}}.font(.caption)
        }.frame(maxWidth:680)
    }
    var modeMenu:some View {
        Menu{Button("Safe Mode"){store.setMode(.safe)};Button("Evil Mode"){store.setMode(.evil)}}label:{HStack(spacing:4){Text(isEvil ? "Evil Mode":"Safe Mode").font(.system(size:13,weight:.medium));Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))}.foregroundStyle(.primary.opacity(0.72))}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Only this chat. New chats start in Safe Mode.").accessibilityLabel("Evil Mode for this chat").accessibilityIdentifier("prometh.mode")
    }
    func transcript(_ c:Conversation)->some View {
        ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:30){ForEach(c.messages){m in messageView(m,chat:c)};Color.clear.frame(height:1).id("bottom")}.frame(maxWidth:760).padding(.horizontal,35).padding(.vertical,30).frame(maxWidth:.infinity)}.onChange(of:c.messages.count){_,_ in if store.isRunning(c.id) || store.voice.isOpen {proxy.scrollTo("bottom",anchor:.bottom)}}.onChange(of:c.messages.last?.text){_,_ in if store.isRunning(c.id) || store.voice.isOpen {proxy.scrollTo("bottom",anchor:.bottom)}}.onChange(of:c.id,initial:true){_,_ in proxy.scrollTo("bottom",anchor:.bottom)}}
    }
    func messageView(_ m:Message,chat:Conversation)->some View {
        VStack(alignment:.leading,spacing:12){if m.role=="user" {HStack{Spacer(minLength:55);VStack(alignment:.leading,spacing:10){Text(m.text).font(.system(size:15)).lineSpacing(5).textSelection(.enabled);ForEach(m.attachments){a in Button{store.previewAttachment=a}label:{Label(a.filename,systemImage:"paperclip")}}}.padding(.horizontal,19).padding(.vertical,14).background(Color.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:21))};HStack{Spacer();Button("Edit"){editText=m.text;editing=m}.buttonStyle(.plain).font(.system(size:10)).foregroundStyle(.secondary)}} else {
                HStack(spacing:8){Text(Product.name).font(.system(size:11,weight:.semibold));if m.status=="streaming"{Text("· Writing").font(.system(size:10)).foregroundStyle(.secondary)}}
                formattedText(m)
                if m.status=="preparing"{ProgressView().controlSize(.small)}
                if let a=m.artifact{ArtifactCard(store:store,artifact:a)}
                if let links=m.sourceLinks,!links.isEmpty {PromethSourcesRow(links:links)}
                if let names=m.appliedSkillNames,!names.isEmpty{Text("Skills: "+names.joined(separator:", ")).font(.system(size:10)).foregroundStyle(.secondary)}
                if m.status != "streaming" && m.status != "preparing" && !m.text.isEmpty{HStack(spacing:13){IconButton(symbol:"doc.on.doc",title:"Copy response"){let board=NSPasteboard.general;board.prepareForNewContents();board.setString(m.text,forType:.string)};IconButton(symbol:"arrow.clockwise",title:m.status=="failed" ? "Retry response":"Regenerate response"){store.regenerate(m)};IconButton(symbol:"speaker.wave.2",title:"Read response aloud"){store.voice.readAloud(m.text)};if m.status=="stopped"{Text("Stopped").font(.caption).foregroundStyle(.secondary)};if m.status=="failed"{Button("Try again"){store.regenerate(m)}.font(.caption)}}.foregroundStyle(.secondary)}
            }}.frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier(m.role == "user" ? "prometh.user":"prometh.reply")
    }
    @ViewBuilder func formattedText(_ message:Message)->some View {let blocks=message.text.components(separatedBy:"```");VStack(alignment:.leading,spacing:14){ForEach(Array(blocks.enumerated()),id:\.offset){i,block in if i%2==1 {Text(block).font(.system(size:13,design:.monospaced)).textSelection(.enabled).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:14))}else{PromethCitationText(text:block, links:message.sourceLinks)}}}.accessibilityElement(children:.combine).accessibilityIdentifier("prometh.reply")}
    var composer:some View {
        VStack(alignment:.leading,spacing:6) {
            if store.dictating {HStack{Text("Listening…").font(.system(size:12)).foregroundStyle(.secondary);Spacer();Button("Finish"){store.voice.finishRecording()};Button("Cancel"){store.cancelDictation()}.font(.system(size:12))}}
            if let c=store.current,!c.attachments.isEmpty {ScrollView(.horizontal){HStack{ForEach(c.attachments){a in HStack{Button{store.previewAttachment=a}label:{Label(a.filename,systemImage:"paperclip").lineLimit(1)}.buttonStyle(.plain);IconButton(symbol:"xmark",title:"Remove attachment"){store.removeAttachment(a)}}.font(.caption).padding(.horizontal,8).padding(.vertical,4).background(Color.primary.opacity(0.05),in:Capsule())}}}}
            ZStack(alignment:.topLeading){if (store.current?.draft ?? "").isEmpty{Text("Message "+Product.name).font(.system(size:16)).foregroundStyle(.tertiary).padding(.top,8).padding(.leading,4).allowsHitTesting(false)};ComposerEditor(text:Binding(get:{store.current?.draft ?? ""},set:{if store.current==nil{store.newChat()};store.setDraft($0)}),onSend:{store.send($0)}).frame(height:min(130,max(36,CGFloat((store.current?.draft.components(separatedBy:"\n").count ?? 1))*21+16)))}
            HStack(spacing:10) {
                plusMenu
                Spacer(minLength:4)
                if !store.skills.filter(\.isEnabled).isEmpty {Text("\(store.skills.filter(\.isEnabled).count) skills").font(.system(size:11)).foregroundStyle(.secondary)}
                modeMenu
                Button{if store.state.preparations[Capability.voice.rawValue]?.status == .ready{if store.current==nil{store.newChat()};store.dictate()}else{prepareVoice()}}label:{Image(systemName:"mic").font(.system(size:16)).foregroundStyle(.secondary).frame(width:28,height:32)}.buttonStyle(.plain).help("Dictate").accessibilityLabel("Dictate")
                trailingAction
            }
        }
        .padding(.horizontal,16).padding(.vertical,12)
        .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:28,style:.continuous))
        .overlay { composerRim }
        .shadow(color:isEvil ? Color.coral.opacity(scheme == .dark ? 0.38:0.24):.clear,radius:14)
        .shadow(color:.black.opacity(scheme == .dark ? 0.18:0.06),radius:16,y:6)
        .animation(reduceMotion ? nil:.easeInOut(duration:0.22),value:isEvil)
        .frame(maxWidth:760).padding(.horizontal,28).frame(maxWidth:.infinity).accessibilityElement(children:.contain).accessibilityIdentifier("prometh.composer")
    }
    var composerRim:some View {
        RoundedRectangle(cornerRadius:28,style:.continuous).strokeBorder(LinearGradient(colors:isEvil ? [Color(hex:0xE06B62),Color(hex:0xD4788C),Color(hex:0xA67BB8)]:[Color.primary.opacity(0.10),Color.primary.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:isEvil ? 1.5:1)
    }
    var plusMenu:some View {
        Menu{Button("Attach a file…"){store.chooseAttachment()};Divider();Menu("Tools"){Toggle("Web search",isOn:$store.state.webSearch);Toggle("Read attachments",isOn:Binding(get:{store.state.fileReadingEnabled != false},set:{store.state.fileReadingEnabled=$0}));Button("All tools…"){store.openCustomize("Tools")}};Menu("Skills"){ForEach(store.skills){skill in Toggle(skill.name,isOn:Binding(get:{store.skills.first{$0.id==skill.id}?.isEnabled ?? false},set:{store.setSkillEnabled(skill.id,$0)}))};if store.skills.isEmpty{Button("Add a skill…"){store.openCustomize("Skills")}};Button("All skills…"){store.openCustomize("Skills")}};if store.connectorsAvailable {Menu("Plugins"){ForEach(Provider.allCases){p in Button("\(p.rawValue) · \((store.state.connections[p.rawValue] ?? .disconnected).rawValue)"){if store.state.connections[p.rawValue] == .connected{sourcePreview=true}else{store.consent=p}}};Button("All plugins…"){store.openCustomize("Plugins")}}}}label:{Image(systemName:"plus").font(.system(size:18,weight:.medium)).foregroundStyle(.primary).frame(width:28,height:32)}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Add")
    }
    @ViewBuilder var trailingAction:some View {
        if store.voice.isOpen {
            Button{store.voice.end()}label:{ZStack{ActionOrb();Image(systemName:"xmark").font(.system(size:13,weight:.bold)).foregroundStyle(.white)}.frame(width:36,height:36)}.buttonStyle(.plain).help("End voice").accessibilityLabel("End voice")
        } else if running || !draftEmpty {
            Button{if let c=store.current,store.isRunning(c.id){store.stop(c.id)}else{store.send()}}label:{ZStack{ActionOrb();Image(systemName:running ? "stop.fill":"arrow.up").font(.system(size:14,weight:.semibold)).foregroundStyle(.white)}.frame(width:36,height:36)}.buttonStyle(.plain).help(running ? "Stop":"Send").accessibilityLabel(running ? "Stop":"Send").accessibilityIdentifier("prometh.send")
        } else {
            Button{openVoice()}label:{ZStack{ActionOrb();VoiceGlyph()}.frame(width:36,height:36)}.buttonStyle(.plain).help("Voice").accessibilityLabel("Voice")
        }
    }
    func prepareVoice(){store.state.selected.insert(.voice);store.resumePreparation(.voice);store.settingsTab="Capabilities";store.settingsOpen=true}
    func openVoice(){
        guard store.state.preparations[Capability.voice.rawValue]?.status == .ready else {prepareVoice();return}
        if store.current==nil {store.newChat()}
        let owner=store.state.selectedChatID
        store.voice.onExchange={user,reply in guard store.state.selectedChatID==owner else{return};store.appendVoiceExchange(user,reply)}
        store.voice.open()
        if !store.voice.denied {store.voice.sampleTurn()}
    }
}
