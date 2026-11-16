import { batteryInfo, commonEventManager } from '@kit.BasicServicesKit';

/** 只在开启时间与电量且收起阅读工具栏时挂载。 */
@Component
export struct ReaderStatusIndicator {
  @State batteryPercent: number = -1;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  private subscriptionId: number = 0;

  aboutToAppear(): void {
    const subscriptionId = ++this.subscriptionId;
    this.refreshBattery();
    commonEventManager.createSubscriber({
      events: [commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED]
    }).then((subscriber: commonEventManager.CommonEventSubscriber): void => {
      if (subscriptionId !== this.subscriptionId) {
        return;
      }
      this.subscriber = subscriber;
      commonEventManager.subscribe(subscriber, (error): void => {
        if (!error && subscriptionId === this.subscriptionId) {
          this.refreshBattery();
        }
      });
      this.refreshBattery();
    }).catch((error: Error): void => {
      console.warn('[ReaderStatusIndicator] battery subscription failed: ' + error.message);
    });
  }

  aboutToDisappear(): void {
    this.subscriptionId++;
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (subscriber !== undefined) {
      commonEventManager.unsubscribe(subscriber, (error): void => {
        if (error) {
          console.warn('[ReaderStatusIndicator] battery unsubscribe failed: ' + error.message);
        }
      });
    }
  }

  private refreshBattery(): void {
    try {
      const percent = batteryInfo.batterySOC;
      this.batteryPercent = Number.isFinite(percent) && percent >= 0 && percent <= 100 ? Math.round(percent) : -1;
    } catch (_error) {
      this.batteryPercent = -1;
    }
  }

  build() {
    Row({ space: 8 }) {
      TextClock()
        .format('HH:mm')
        .fontSize(12)
        .fontColor(Color.White)
      if (this.batteryPercent >= 0) {
        Text(this.batteryPercent + '%')
          .fontSize(12)
          .fontColor(Color.White)
          .accessibilityText('电量百分之' + this.batteryPercent)
      }
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .borderRadius(12)
    .backgroundColor('#B31C1C1E')
    .hitTestBehavior(HitTestMode.None)
  }
}
