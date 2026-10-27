import SwiftUI

struct Dreamworld: View {
    var evil=false
    var muted=false
    var body: some View {
        GeometryReader { geo in
            Image(nsImage:Resources.image("onboarding-dreamworld.png"))
                .resizable().scaledToFill().frame(width:geo.size.width,height:geo.size.height).clipped()
                .saturation(evil ? 0:(muted ? 0:0.78))
                .preference(key:DreamworldFrameKey.self,value:geo.frame(in:.global))
                .overlay {
                    if evil {
                        Color.black.opacity(0.88)
                        LinearGradient(colors:[Color(hex:0x4A090C).opacity(0.72),.clear],startPoint:.bottom,endPoint:.top)
                        LinearGradient(colors:[.black.opacity(0.55),.clear],startPoint:.top,endPoint:.center)
                    } else if muted {
                        Color.black.opacity(0.72)
                        LinearGradient(colors:[.black.opacity(0.28),.clear],startPoint:.top,endPoint:.center)
                    } else {
                        LinearGradient(colors:[.black.opacity(0.60),.black.opacity(0.12)],startPoint:.leading,endPoint:.trailing)
                    }
                }
        }.ignoresSafeArea()
    }
}
struct DreamworldFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next=nextValue(); if next != .zero { value=next } }
}
struct CapabilityPhoto: View {
    var dreamworld: CGRect
    var body: some View {
        GeometryReader { geo in
            let card=geo.frame(in:.global)
            Image(nsImage:Resources.image("onboarding-dreamworld.png"))
                .resizable().scaledToFill()
                .frame(width:dreamworld.width,height:dreamworld.height)
                .offset(x:dreamworld.minX-card.minX,y:dreamworld.minY-card.minY)
                .overlay(Color.black.opacity(0.36))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
struct PanelHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct OnboardingView: View {
    @ObservedObject var store:PromethStore
    @Environment(\.accessibilityReduceMotion) var reduce
    @State private var dreamworldFrame: CGRect = .zero
    @State private var panelHeight: CGFloat = 0
    var isScenic:Bool {store.state.step == 0 || store.state.step == 2}
    var columnWidth: CGFloat {switch store.state.step {case 1:1160;case 2:640;case 3:1040;default:760}}
    var body: some View {
        ZStack {
            Dreamworld(evil:store.state.step==2,muted:!isScenic)
            VStack(spacing:0) {
                HStack {Brand();Spacer();Text("On-device AI").font(.system(size:12))}
                    .padding(.horizontal,52).padding(.top,36).padding(.bottom,20)
                GeometryReader { geo in
                    let roomy = geo.size.width >= 1400 || geo.size.height >= 900
                    let maxWidth: CGFloat = switch (store.state.step, roomy) {
                    case (1, true): min(1380, geo.size.width - 140)
                    case (2, true): 820
                    default: columnWidth
                    }
                    ScrollView {
                        VStack(spacing:0) {
                            Spacer(minLength:28)
                            Group {switch store.state.step {case 0:welcome;case 1:capabilities(roomy);case 2:EvilReveal(store:store,spacious:roomy);default:preparation}}
                                .frame(maxWidth:maxWidth,alignment:store.state.step == 2 && roomy ? .center : .leading)
                                .padding(.horizontal,40)
                            Spacer(minLength:28)
                        }
                        .frame(minWidth:geo.size.width,minHeight:geo.size.height)
                    }
                }
                HStack {
                    if store.state.step>0 {Button{store.back()}label:{Label("Back",systemImage:"arrow.left")}.buttonStyle(.plain).accessibilityIdentifier("prometh.back")}
                    Spacer()
                    Text("\(store.state.step+1) / 4").monospacedDigit().accessibilityIdentifier("prometh.step")
                }.font(.system(size:12)).padding(.horizontal,52).padding(.vertical,23)
                .accessibilityElement(children: .contain)
            }.foregroundStyle(Color.white)
        }
        .onPreferenceChange(DreamworldFrameKey.self) { dreamworldFrame=$0 }
        .animation(reduce ? nil:.easeInOut(duration:0.22),value:store.state.step)
    }
    var welcome: some View {
        VStack(alignment:.leading,spacing:27) {
            Text(Product.headline).font(.system(size:64,weight:.medium)).tracking(-2.5)
            VStack(alignment:.leading,spacing:8) {
                Text("Fully private.")
                Text("No accounts.")
                Text("Full control.")
                Text("Your choice of models.")
            }.font(.system(size:36,weight:.regular)).tracking(-0.9).foregroundStyle(.white.opacity(0.90))
            Text("Runs on your Mac.").font(.system(size:15)).foregroundStyle(.white.opacity(0.7)).padding(.top,4)
            Button("Get started"){store.next()}.buttonStyle(WelcomeButton()).padding(.top,12)
        }
    }
    var preparing:[Capability] {Capability.allCases.filter{store.state.selected.contains($0)}}
    func capabilities(_ roomy:Bool)->some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:roomy ? 18:14) {
                Text("What capabilities do you want to enable?").font(.system(size:roomy ? 42:32,weight:.medium)).tracking(roomy ? -1.3:-1.05)
                Text("Chat is the default.").font(.system(size:roomy ? 18:16)).foregroundStyle(.white.opacity(0.72))
            }
            HStack(alignment:.top,spacing:roomy ? 36:22) {ForEach(Capability.allCases){capabilityCard($0,roomy:roomy)}}
                .padding(.top,roomy ? 92:40)
            Text(store.macSpecs.summary).font(.system(size:roomy ? 15:13)).foregroundStyle(.white.opacity(0.55))
                .padding(.top,roomy ? 72:32)
            HStack(alignment:.center,spacing:16) {
        Text(String(format: "%.2f GB", locale: Locale(identifier: "en_US_POSIX"), store.total)).font(.system(size:roomy ? 17:15,weight:.medium)).monospacedDigit().foregroundStyle(.white.opacity(0.72)).accessibilityIdentifier("prometh.total")
                Spacer()
                Button("Continue"){store.next()}.buttonStyle(WelcomeButton())
            }.padding(.top,roomy ? 56:28)
        }
    }
    func capabilityCard(_ capability:Capability,roomy:Bool)->some View {
        let selected=store.state.selected.contains(capability),available=store.available(capability),isChat=capability == .chat
        return Button{store.toggle(capability)}label:{
            HStack(alignment:.center,spacing:12) {
                CapabilityIcon(capability:capability,size:roomy ? 60:52).opacity(available ? 1:0.4)
                VStack(alignment:.leading,spacing:7) {
                    HStack(alignment:.center) {
                        Text(capability.rawValue).font(.system(size:roomy ? 20:18,weight:.medium)).tracking(-0.3)
                        Spacer(minLength:4)
                        if isChat {
                            Text("Default").font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.62))
                        } else if selected && available {
                            Image(systemName:"checkmark").font(.system(size:11,weight:.bold))
                                .frame(width:18,height:18)
                                .background(.white,in:Circle())
                                .foregroundStyle(Color.sovereignInk)
                        } else {
                            Circle().stroke(.white.opacity(available ? 0.38:0.18),lineWidth:1.2).frame(width:18,height:18)
                        }
                    }
                    Text(available ? capability.phrase:store.limitLabel(capability))
                        .font(.system(size:13)).foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                    Text("\(store.sizeLabel(capability))").font(.system(size:12)).foregroundStyle(.white.opacity(0.42)).monospacedDigit()
                }
            }
            .padding(.horizontal,roomy ? 22:18).padding(.vertical,roomy ? 26:20).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:roomy ? 164:132)
            .foregroundStyle(.white.opacity(available ? 1:0.45))
            .background {
                let shape=RoundedRectangle(cornerRadius:18,style:.continuous)
                ZStack {
                    shape.fill(.white.opacity(0.07))
                    if selected && available && dreamworldFrame.width > 1 {
                        CapabilityPhoto(dreamworld:dreamworldFrame).clipShape(shape)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(.white.opacity((selected && available) || isChat ? 0.7:0.14),lineWidth:(selected && available) || isChat ? 1.5:1))
            .animation(reduce ? nil:.easeInOut(duration:0.28),value:selected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prometh.capability.\(capability.rawValue.lowercased())")
        .accessibilityLabel("\(capability.rawValue), \(isChat ? "default":selected ? "selected":"not selected"), \(store.sizeLabel(capability)). \(available ? capability.phrase:store.fitNote(capability))")
    }
    var preparation: some View {
        VStack(alignment:.leading,spacing:27) {
            VStack(alignment:.leading,spacing:10) {
                Text("Preparing your AI").font(.system(size:37,weight:.medium)).tracking(-1.2)
                Text(store.chatReady ? "Chat is ready. Open it while the others finish.":"You can start chatting as soon as Chat is ready.")
                    .font(.system(size:14)).foregroundStyle(.white.opacity(0.72))
            }
            HStack(alignment:.top,spacing:24) {
                preparationCard {
                    VStack(alignment:.leading,spacing:2) {
                        ForEach(Array(preparing.enumerated()),id:\.element.id){index,capability in
                            if index > 0 {Divider().opacity(0.45)}
                            PreparationRow(store:store,capability:capability)
                        }
                        Divider().opacity(0.45).padding(.top,6)
                        HStack {
                            Text("\(store.state.selected.filter{store.state.preparations[$0.rawValue]?.status == .ready}.count) of \(store.state.selected.count) ready").font(.system(size:12)).foregroundStyle(.secondary)
                            Spacer();Button("Open chat"){store.enterChat()}.buttonStyle(PrimaryButton()).disabled(!store.chatReady).opacity(store.chatReady ? 1:0.5).accessibilityIdentifier("prometh.open-chat")
                        }.padding(.top,12)
                    }
                }
                if store.connectorsAvailable {
                preparationCard {
                    VStack(alignment:.leading,spacing:18) {
                        Text("Connect your apps").font(.system(size:20,weight:.medium)).tracking(-0.4)
                        Text("While you wait, add the apps you want your AI to work with.").font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)
                        ConnectorsList(store:store)
                        Text("Optional. You can do this later in Customize.").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }
                }
            }
            .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
        }
    }
    func preparationCard<Content:View>(@ViewBuilder content:()->Content)->some View {
        content().padding(22)
            .fixedSize(horizontal:false,vertical:true)
            .background { GeometryReader { proxy in Color.clear.preference(key:PanelHeightKey.self,value:proxy.size.height) } }
            .frame(maxWidth:.infinity,minHeight:panelHeight,alignment:.topLeading)
            .glassPanel().foregroundStyle(Color.primary)
    }
}
struct WelcomeButton:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {configuration.label.font(.system(size:14,weight:.semibold)).foregroundStyle(Color.sovereignInk).padding(.horizontal,30).padding(.vertical,15).background(.white.opacity(configuration.isPressed ? 0.8:0.96),in:Capsule())}
}
struct EvilSwitch: View {
    @Binding var isOn: Bool
    var large = false
    var showsLabel = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                if showsLabel { Text("Enable Evil Mode").font(.system(size: large ? 18:16, weight: .medium)) }
                ZStack {
                    Capsule()
                        .fill(isOn ? Color(hex: 0xC44848) : Color.white.opacity(0.14))
                    Capsule()
                        .strokeBorder(Color.white.opacity(isOn ? 0.16 : 0.22), lineWidth: 1)
                    Circle()
                        .fill(Color.white)
                        .frame(width: large ? 20:16, height: large ? 20:16)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .frame(maxWidth: .infinity, alignment: isOn ? .trailing : .leading)
                        .padding(large ? 3:3)
                }
                .frame(width: large ? 52:40, height: large ? 28:22)
            }
        }
        .buttonStyle(.plain)
        .animation(reduce ? nil : .easeInOut(duration: 0.18), value: isOn)
        .accessibilityLabel("Enable Evil Mode")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
struct EvilReveal:View {
    @ObservedObject var store:PromethStore
    var spacious = false
    var body:some View {
        Group {
            if spacious { spaciousBody } else { compactBody }
        }
    }
    var compactBody:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Evil Mode").font(.system(size:60,weight:.medium)).tracking(-2.2)
            Text("Explore with fewer refusals.").font(.system(size:28,weight:.regular)).tracking(-0.6)
            Text("An optional locally running alternative for this conversation. Behavior depends on the model; zero refusals are not guaranteed.")
                .font(.system(size:17)).foregroundStyle(.white.opacity(0.82)).lineSpacing(4).fixedSize(horizontal:false,vertical:true).frame(maxWidth:460,alignment:.leading)
            EvilSwitch(isOn:evilOn).padding(.top,10)
            continueButton.padding(.top,4)
        }.frame(maxWidth:640,alignment:.leading)
    }
    var spaciousBody:some View {
        VStack(spacing:0) {
            Text("Evil Mode").font(.system(size:84,weight:.medium)).tracking(-2.8)
            Text("Explore with fewer refusals.").font(.system(size:36,weight:.regular)).tracking(-0.8).padding(.top,36)
            Text("An optional locally running alternative for this conversation. Behavior depends on the model; zero refusals are not guaranteed.")
                .font(.system(size:20)).foregroundStyle(.white.opacity(0.82)).lineSpacing(6).multilineTextAlignment(.center)
                .frame(maxWidth:520).padding(.top,28)
            Text("Enable Evil Mode").font(.system(size:18,weight:.medium)).padding(.top,64)
            EvilSwitch(isOn:evilOn,large:true,showsLabel:false).padding(.top,18)
            continueButton.padding(.top,40)
        }
        .frame(maxWidth:.infinity)
    }
    var evilOn:Binding<Bool> {Binding(get:{store.state.defaultMode == .evil},set:{store.state.defaultMode = $0 ? .evil:.safe})}
    var continueButton:some View {Button(store.revealInChat ? "Done":"Continue"){store.chooseEvil(store.state.defaultMode == .evil)}.buttonStyle(PrimaryButton(coral:true))}
}
struct PreparationRow:View {
    @ObservedObject var store:PromethStore;let capability:Capability
    var body:some View {
        let preparation=store.state.preparations[capability.rawValue] ?? Preparation()
        HStack(alignment:.center,spacing:12) {
            CapabilityIcon(capability:capability,size:34)
            VStack(alignment:.leading,spacing:8) {
                HStack(alignment:.center,spacing:8) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(capability.rawValue).font(.system(size:14,weight:.medium))
                        Text(detail(preparation)).font(.system(size:11)).foregroundStyle(preparation.status == .failed ? Color.red:Color.secondary)
                    }
                    Spacer(minLength:8)
                    controls(preparation)
                }
                progress(preparation)
            }
        }
        .padding(.vertical,11)
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(capability.rawValue), \(detail(preparation))")
        .accessibilityValue("\(Int(preparation.progress*100)) percent")
    }
    @ViewBuilder func controls(_ p:Preparation)->some View {
        switch p.status {
        case .ready:Text("Ready").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
        case .paused,.cancelled,.queued:Button("Resume"){store.resumePreparation(capability)}.buttonStyle(.bordered).controlSize(.small)
        case .failed:Button("Retry"){store.retryPreparation(capability)}.buttonStyle(.bordered).controlSize(.small)
        default:
            HStack(spacing:2) {
                IconButton(symbol:"pause",title:"Pause \(capability.rawValue)"){store.pausePreparation(capability)}
                IconButton(symbol:"xmark",title:"Cancel \(capability.rawValue)"){store.cancelPreparation(capability)}
            }
        }
    }
    func progress(_ p:Preparation)->some View {
        Capsule().fill(Color.primary.opacity(0.08)).frame(height:3)
            .overlay(alignment:.leading){GeometryReader{geo in Capsule().fill(barColor).frame(width:max(p.progress > 0 ? 3:0,geo.size.width*p.progress))}}
            .clipShape(Capsule())
            .accessibilityLabel("\(capability.rawValue) preparation")
    }
    var barColor:Color {switch capability{case .chat:Color(hex:0x3AA0D8);case .voice:Color(hex:0x6E5CC0);case .images:Color(hex:0xD7A63A);case .video:Color(hex:0xE36B5C)}}
    func detail(_ p:Preparation)->String {
        if p.status == .failed{return store.modelDetails[capability.rawValue] ?? "Preparation interrupted. Try again."}
        if p.status == .ready{return capability.phrase}
        if p.status == .paused || p.status == .cancelled{return p.status.rawValue}
        if p.status == .queued{return "Waiting"}
        if !store.isPreview {return store.modelDetails[capability.rawValue] ?? p.status.rawValue}
        return p.status.rawValue
    }
}
struct ConnectorsList:View {
    @ObservedObject var store:PromethStore
    var body:some View {
        VStack(spacing:0) {
            ForEach(Provider.allCases){provider in
                let status=store.state.connections[provider.rawValue] ?? .disconnected
                HStack(spacing:12) {
                    PromethProviderLogo(provider:provider,size:25)
                    VStack(alignment:.leading,spacing:4) {
                        Text(provider.rawValue).font(.system(size:13,weight:.medium))
                        Text(status.label)
                            .font(.system(size:10))
                            .foregroundStyle(status == .expired ? .orange : status == .connecting ? .primary : .secondary)
                    }
                    Spacer()
                    Button(status.buttonTitle) {
                        if status == .connected { store.disconnect(provider) }
                        else if status != .connecting { store.consent = provider }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(status == .connecting)
                }.padding(.vertical,11)
                if provider != Provider.allCases.last{Divider().opacity(0.45)}
            }
        }
    }
}
