import { Component, OnInit, signal } from '@angular/core';
import { ApiService, Site } from './api.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App implements OnInit {
  health = signal('unknown');
  sites = signal<Site[]>([]);
  onHand = signal<any[]>([]);
  selectedSite = signal('');

  constructor(private api: ApiService) {}

  ngOnInit() {
    this.api.health().subscribe({
      next: res => this.health.set(res.status ?? 'ok'),
      error: () => this.health.set('down')
    });
  }

  load() {
    this.api.health().subscribe({
      next: res => this.health.set(res.status ?? 'ok'),
      error: () => this.health.set('down')
    });

    this.api.sites().subscribe({
      next: s => this.sites.set(s),
      error: err => console.error('sites() failed', err)
    });
  }

  loadOnHand(siteCode: string) {
    this.selectedSite.set(siteCode);

    this.api.onHand(siteCode).subscribe({
      next: rows => this.onHand.set(rows),
      error: err => console.error('onHand() failed', err)
    });
  }
}