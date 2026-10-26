import SwiftUI

struct PromethSettingsView:View {
    @ObservedObject var store:PromethStore
    @State var resetConfirmation=false
    @State var samplesConfirmation=false
    var tabs:[String] {
        var names = store.isPreview ? ["Appearance","Capabilities","Privacy & data","Preview"] : ["Appearance","Capabilities","Privacy & data"]
        names.append("Advanced")
        return names
    }
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:7) {
                Brand().padding(.bottom,25)
                ForEach(tabs,id:\.self){tab in
                    if tab == "Privacy & data" {Divider().padding(.vertical,10)}
                    Button{store.settingsTab=tab}label:{Text(tab).font(.system(size:13,weight:store.settingsTab==tab ? .medium:.regular)).frame(maxWidth:.infinity,alignment:.leading).padding(11).background(store.settingsTab==tab ? Color.primary.opacity(0.07):.clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain).accessibilityIdentifier("prometh.settings.\(tab)")
                }
                Spacer()
                Text("Saved on this Mac").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(22).frame(width:210).background(.primary.opacity(0.018))
            Divider()
            VStack(alignment:.leading,spacing:22) {
                HStack{Text(store.settingsTab).font(.system(size:27,weight:.medium)).tracking(-0.8);Spacer();IconButton(symbol:"xmark",title:"Close settings"){store.settingsOpen=false}}
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        switch store.settingsTab {
                        case "Appearance":appearance
                        case "Capabilities":capabilities
                        case "Privacy & data":privacy
                        case "Advanced":advanced
                        default:preview
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.padding(28).frame(maxWidth:.infinity)
        }.frame(width:850,height:640)
            .sheet(item:$store.consent){ConsentView(store:store,provider:$0)}
            .onExitCommand{store.settingsOpen=false}
            .confirmationDialog("Clear this prototype's data?",isPresented:$resetConfirmation){Button("Clear & restart",role:.destructive){store.resetData()};Button("Cancel",role:.cancel){}}message:{Text("Only this prototype's chats, choices and connectors are reset.")}
            .confirmationDialog("Replace conversations with samples?",isPresented:$samplesConfirmation){Button("Restore samples",role:.destructive){store.restoreSamples()};Button("Cancel",role:.cancel){}}
    }
    var appearance:some View {
        VStack(alignment:.leading,spacing:24) {
            Text("Choose your preferred appearance.").foregroundStyle(.secondary)
            Picker("Appearance",selection:$store.state.appearance){ForEach(["Light","Dark","System"],id:\.self){Text($0)}}.pickerStyle(.segmented)
            HStack(spacing:14){appearanceSample(dark:false);appearanceSample(dark:true)}
            Text("Evil Mode has its own accent in each chat, independent of appearance.").font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
    func appearanceSample(dark:Bool)->some View {
        VStack(alignment:.leading,spacing:12){HStack{RoundedRectangle(cornerRadius:3).fill(dark ? Color.white.opacity(0.1):Color.black.opacity(0.07)).frame(width:44,height:12);Spacer()};Spacer();RoundedRectangle(cornerRadius:5).fill(dark ? Color.white.opacity(0.08):Color.black.opacity(0.06)).frame(height:28)}.padding(18).frame(height:140).background(dark ? Color(hex:0x22252B):Color(hex:0xF8F7F4),in:RoundedRectangle(cornerRadius:15)).overlay(RoundedRectangle(cornerRadius:15).stroke(.primary.opacity(0.1)))
    }
    var capabilities:some View {
        VStack(alignment:.leading,spacing:18){Text(store.macSpecs.summary).font(.system(size:12)).foregroundStyle(.secondary);Text(String(format: "%.2f GB selected", locale: Locale(identifier: "en_US_POSIX"), store.total)).font(.headline)
            ForEach(Capability.allCases){c in
                VStack(alignment:.leading,spacing:8){
                    if store.state.selected.contains(c){
                        PreparationRow(store:store,capability:c)
                        HStack{Text("\(store.sizeLabel(c))").font(.caption).foregroundStyle(.secondary);Spacer();Button("Download / verify"){store.verifyPreparation(c)};if c != .chat{Button("Remove"){store.toggle(c)}}}
                    }else{
                        HStack(spacing:12){Text(c.rawValue).font(.system(size:15,weight:.medium));Spacer();Text("\(store.sizeLabel(c))").font(.caption).foregroundStyle(.secondary);Button("Add"){store.toggle(c);if store.state.selected.contains(c){store.resumePreparation(c)}}}
                        Text(store.available(c) ? c.detail:store.fitNote(c)).font(.caption).foregroundStyle(.secondary).opacity(store.available(c) ? 1:0.7)
                    }
                }.padding(17).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:14))
            }
            VStack(alignment:.leading,spacing:10){HStack{Text("Evil chat · optional").font(.headline);Spacer();Button("Download / verify"){store.prepareEvil()}};DisclosureGroup("Details"){Text(store.modelDetails["Evil"] ?? "Qwen3.5 9B Heretic v2 · Evil · 5.63 GB").font(.caption).foregroundStyle(.secondary)}}.padding(17).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:14))
            Text("Downloads show selected weight sizes, not working memory. Heavy chat, speech, image and video jobs run one at a time; the previous engine unloads before another family runs. Keep 12 GiB free for macOS, plus selected downloads.").font(.caption).foregroundStyle(.secondary)
            if store.state.hardware == .storage {Button("Review capability choices"){store.settingsOpen=false;store.state.step=1;store.state.onboardingComplete=false}}
        }
    }
    var advanced:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Search and reading stay on this Mac. API providers are optional and are never the default.").font(.system(size:13)).foregroundStyle(.secondary)
            DisclosureGroup("Search status") {
                VStack(alignment:.leading,spacing:8) {
                    Text(SearXNGSupervisor.shared.statusText).font(.system(size:12, design:.monospaced))
                    Button("Restart search") {
                        SearXNGSupervisor.shared.stop()
                        Task { await SearXNGSupervisor.shared.start() }
                    }
                    Button("SearXNG source code") {
                        if let url = URL(string: PromethSearchCredits.searxngSourceURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }.padding(.top, 8)
            }
            DisclosureGroup("Page reader") {
                Text("On-device reader. No API key.").font(.system(size:12)).foregroundStyle(.secondary).padding(.top, 8)
            }
            if PromethFlags.keyedSearchProviders {
                DisclosureGroup("API search providers") {
                    WebBrowsingSettingsView()
                        .frame(minHeight: 280)
                        .padding(.top, 8)
                }
            }
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--prometh-flags") }) {
                Text("Launch flags are active for this session.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var privacy:some View {
        VStack(alignment:.leading,spacing:18){Text("Your data stays on this Mac.").font(.headline);Text("No product account. Chats, skills and preferences are stored in this app's own folder.").foregroundStyle(.secondary).lineSpacing(5);Button("Export current conversation…"){store.exportChat()};Button("Show local data folder"){NSWorkspace.shared.open(store.persistence.directory)};Divider();Text("About local inference").font(.headline);Text("Local models run in Prometh’s own packaged runtimes. Downloads come directly from Hugging Face at pinned revisions with verified checksums. Web search and connected apps send requests only when enabled. Working memory varies by task; 16 GB hardware certification is pending. Video generation is silent text-to-video; editing currently supports real trimming.").font(.system(size:12)).lineSpacing(5).foregroundStyle(.secondary);Button("Clear local data…",role:.destructive){resetConfirmation=true}}
    }
    var preview:some View {
        VStack(alignment:.leading,spacing:17){Button("Restart onboarding"){store.restartOnboarding()};Picker("Hardware scenario",selection:Binding(get:{store.state.hardware},set:{store.setHardware($0)})){ForEach(Hardware.allCases,id:\.self){Text($0.rawValue)}};Text("Actual Mac: "+store.macSpecs.summary).font(.caption).foregroundStyle(.secondary);Text("Scenarios demonstrate availability. They do not measure model requirements.").font(.caption).foregroundStyle(.secondary);Divider();Toggle("Fail capability preparation",isOn:Binding(get:{store.failPreparation},set:{store.setPreparationFailure($0)}));Toggle("Fail next chat or media request",isOn:$store.failNextResponse);Toggle("Voice permission denied scenario",isOn:$store.voice.denied);Button("Show expired Gmail connector"){store.expireConnection();store.openCustomize("Plugins")};Button("Restore sample conversations…"){samplesConfirmation=true};Button("Clear local data…",role:.destructive){resetConfirmation=true}}
    }
}
struct CustomizeView:View {
    @ObservedObject var store:PromethStore
    var sections:[String] {store.connectorsAvailable ? ["Plugins","Tools","Skills"]:["Tools","Skills"]}
    var section:Binding<String> {Binding(get:{sections.contains(store.customizeSection) ? store.customizeSection:sections[0]},set:{store.customizeSection=$0})}
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) {
                    Text("Customize").font(.system(size:27,weight:.medium)).tracking(-0.8)
                    Text("Plugins, tools and skills.").font(.system(size:13)).foregroundStyle(.secondary)
                }
                Spacer()
                IconButton(symbol:"xmark",title:"Close Customize"){store.customizeOpen=false}
            }
            Picker("Customize",selection:section){ForEach(sections,id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                Group {switch section.wrappedValue {case "Tools":ToolsPage(store:store);case "Skills":SkillsPage(store:store);default:PluginsPage(store:store)}}.frame(maxWidth:.infinity,alignment:.leading)
            }.defaultScrollAnchor(.top).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.padding(28).frame(width:720,height:640,alignment:.topLeading)
            .sheet(item:$store.consent){ConsentView(store:store,provider:$0)}
            .onExitCommand{store.customizeOpen=false}
    }
}
struct PluginsPage:View {
    @ObservedObject var store:PromethStore
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Apps your AI can use.").foregroundStyle(.secondary)
            ConnectorsList(store:store)
            TextField("Connection broker HTTPS address",text:Binding(get:{store.state.connectorBrokerURL ?? ""},set:{store.state.connectorBrokerURL=$0})).textFieldStyle(.roundedBorder)
            Text("Optional. A Prometh broker keeps the service key off this Mac app and opens real authorization in your browser. Local AI works without a connection.").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
}
struct ToolsPage:View {
    @ObservedObject var store:PromethStore
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            Text("What your AI is allowed to do.").foregroundStyle(.secondary)
            toolRow("Web search",detail:"Find information and include sources in replies.",enabled:$store.state.webSearch)
            Divider()
            toolRow("Read attachments",detail:"Work with images, documents, audio and video you attach.",enabled:Binding(get:{store.state.fileReadingEnabled != false},set:{store.state.fileReadingEnabled=$0}))
            Text("Web search runs on this Mac and includes sources in replies. Pages are fetched only when search is enabled. Only files you choose are read.").font(.system(size:11)).foregroundStyle(.secondary)
        }
    }
    func toolRow(_ name:String,detail:String,enabled:Binding<Bool>)->some View {
        HStack(alignment:.top,spacing:24){VStack(alignment:.leading,spacing:7){Text(name).font(.system(size:15,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)};Spacer();Toggle(name,isOn:enabled).labelsHidden().toggleStyle(.switch).accessibilityLabel(name)}
    }
}
struct SkillsPage:View {
    @ObservedObject var store:PromethStore
    @State var editingSkill:SkillRecord?
    @State var deletingSkill:UUID?
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            Text("Reusable instructions for how your AI works.").foregroundStyle(.secondary)
            HStack{Button("Add skill"){editingSkill=SkillRecord(name:"",instructions:"")}.buttonStyle(.borderedProminent);Button("Import file…"){store.chooseSkillFile()}}
            if store.skills.isEmpty {
                VStack(alignment:.leading,spacing:12){Text("No skills added").font(.system(size:18,weight:.medium));Text("Create a skill or import a Markdown file. For example, ask for concise answers or a particular writing style.").font(.system(size:13)).lineSpacing(4).foregroundStyle(.secondary);Button("Add “Concise answers”"){store.saveSkill(SkillRecord(name:"Concise answers",instructions:"Keep answers concise. Start with the answer and avoid unnecessary explanation."))}}.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:15))
            }
            ForEach(store.skills){skill in
                VStack(alignment:.leading,spacing:13){HStack{Text(skill.name).font(.system(size:15,weight:.medium));Spacer();Toggle(skill.name,isOn:Binding(get:{store.skills.first{$0.id==skill.id}?.isEnabled ?? false},set:{store.setSkillEnabled(skill.id,$0)})).labelsHidden().toggleStyle(.switch).accessibilityLabel("Enable "+skill.name)};Text(skill.instructions).font(.system(size:12)).lineSpacing(4).foregroundStyle(.secondary).lineLimit(3);HStack{Button("Edit"){editingSkill=skill};Spacer();Button("Delete",role:.destructive){deletingSkill=skill.id}}.buttonStyle(.borderless).font(.system(size:12))}.padding(18).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:14))
            }
            Text("Enabled skills apply to new replies. Concise and bullet-point styles are included with the instructions sent to the local model.").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
        }
        .sheet(item:$editingSkill){skill in PromethSkillEditor(skill:skill){store.saveSkill($0);editingSkill=nil}}
        .confirmationDialog("Delete this skill?",isPresented:Binding(get:{deletingSkill != nil},set:{if !$0{deletingSkill=nil}})){Button("Delete skill",role:.destructive){if let id=deletingSkill{store.deleteSkill(id)};deletingSkill=nil};Button("Cancel",role:.cancel){deletingSkill=nil}}
    }
}
struct PromethSkillEditor:View {
    @Environment(\.dismiss) var dismiss
    @State var skill:SkillRecord
    let onSave:(SkillRecord)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:19){Text("Skill").font(.system(size:25,weight:.medium));TextField("Skill name",text:$skill.name).textFieldStyle(.roundedBorder);Text("Instructions").font(.system(size:13,weight:.medium));TextEditor(text:$skill.instructions).accessibilityLabel("Skill instructions").font(.system(size:13)).padding(10).frame(height:220).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12));Toggle("Enable for new replies",isOn:$skill.isEnabled);HStack{Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("Save skill"){onSave(skill)}.buttonStyle(PrimaryButton()).disabled(skill.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || skill.instructions.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(28).frame(width:560)
    }
}
struct ConsentView:View {
    @ObservedObject var store:PromethStore
    let provider:Provider
    var body:some View {
        VStack(alignment:.leading,spacing:22){HStack{PromethProviderLogo(provider:provider,size:35);Spacer();Brand()};Text("Connect \(provider.rawValue)").font(.system(size:27,weight:.medium));Text("Your browser will open a real authorization page. Connected app requests use the optional cloud connection service.").foregroundStyle(.secondary);Text(provider.access).font(.system(size:13));Text("Local AI does not need an account. Connections require a configured Prometh broker; its project secret stays on the broker.").font(.caption).foregroundStyle(.secondary);HStack{Button("Cancel"){store.consent=nil};Spacer();Button("Continue in browser"){store.connect(provider)}.buttonStyle(PrimaryButton())}}.padding(32).frame(width:480)
    }
}
